import Darwin
import Foundation

actor TrainingRunWorkerChildProcess {
  enum ProcessError: Error, Sendable, Equatable {
    case alreadyStarted
    case outputOpenFailed(path: String, code: Int32)
    case outputInspectionFailed(path: String, code: Int32)
    case unsafeOutput(path: String)
    case unexpectedOutputOwner(path: String, expected: UInt32, actual: UInt32)
    case unsafeOutputPermissions(path: String, mode: UInt16)
    case launchFailed(path: String, reason: String)
    case executableChanged(path: String)
    case signalFailed(processID: Int32, signal: Int32, code: Int32)
  }

  typealias ExecutableValidation = @Sendable (URL) throws -> (
    url: URL,
    identity: TrainingRunWorkerExecutableIdentity
  )

  private let executableValidation: ExecutableValidation
  private var processID: pid_t?
  private var exit: TrainingRunWorkerProcessExit?
  private var waiters: [CheckedContinuation<TrainingRunWorkerProcessExit, Never>] = []
  private var monitorTask: Task<Void, Never>?
  private var started = false
  private var administrativeTerminationRequested = false
  private var administrativeTerminationFailure: ProcessError?

  init(
    executableValidation: @escaping ExecutableValidation =
      TrainingRunWorkerExecutableIdentity.validated
  ) {
    self.executableValidation = executableValidation
  }

  deinit {
    monitorTask?.cancel()
  }

  func start(
    executableURL: URL,
    arguments: [String],
    standardOutputURL: URL,
    standardErrorURL: URL,
    expectedExecutableIdentity: TrainingRunWorkerExecutableIdentity? = nil
  ) async throws -> Int32 {
    guard !started else { throw ProcessError.alreadyStarted }
    let outputDescriptor = try appendDescriptor(for: standardOutputURL)
    let errorDescriptor: Int32
    do {
      errorDescriptor = try appendDescriptor(for: standardErrorURL)
    } catch {
      Darwin.close(outputDescriptor)
      throw error
    }
    defer {
      Darwin.close(outputDescriptor)
      Darwin.close(errorDescriptor)
    }

    let executable = try executableValidation(executableURL)
    if let expectedExecutableIdentity,
      executable.identity != expectedExecutableIdentity
    {
      throw ProcessError.executableChanged(path: executableURL.path)
    }

    let spawnedPID = try spawn(
      executableURL: executable.url,
      arguments: arguments,
      outputDescriptor: outputDescriptor,
      errorDescriptor: errorDescriptor
    )
    processID = spawnedPID
    started = true
    startExitMonitor()

    do {
      let identityAfterLaunch = try executableValidation(executableURL)
      guard identityAfterLaunch.identity == executable.identity else {
        throw ProcessError.executableChanged(path: executableURL.path)
      }
    } catch {
      do {
        try signalOwnedProcess(SIGKILL)
        _ = await waitForExit()
      } catch {
        throw ProcessError.launchFailed(
          path: executable.url.path,
          reason: "post-launch validation failed and child cleanup failed: \(error)"
        )
      }
      if let processError = error as? ProcessError {
        throw processError
      }
      throw ProcessError.executableChanged(path: executableURL.path)
    }
    return spawnedPID
  }

  func waitForExit() async -> TrainingRunWorkerProcessExit {
    if let exit { return exit }
    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func terminate() {
    guard exit == nil else { return }
    administrativeTerminationRequested = true
    do {
      try signalOwnedProcess(SIGTERM)
    } catch {
      administrativeTerminationFailure = error as? ProcessError
    }
  }

  func hardTerminate() {
    guard exit == nil else { return }
    administrativeTerminationRequested = true
    do {
      try signalOwnedProcess(SIGKILL)
    } catch {
      administrativeTerminationFailure = error as? ProcessError
    }
  }

  func wasAdministrativelyTerminated() -> Bool {
    administrativeTerminationRequested
  }

  func administrativeTerminationError() -> ProcessError? {
    administrativeTerminationFailure
  }

  private func startExitMonitor() {
    monitorTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if await self.pollForExit() { return }
        do {
          try await Task.sleep(for: .milliseconds(20))
        } catch {
          return
        }
      }
    }
  }

  private func pollForExit() -> Bool {
    guard exit == nil, let processID else { return true }
    var status: Int32 = 0
    let result = Darwin.waitpid(processID, &status, WNOHANG)
    if result == 0 { return false }
    if result == processID {
      record(Self.processExit(from: status))
      return true
    }
    if result < 0, errno == EINTR { return false }
    if result < 0 {
      record(
        TrainingRunWorkerProcessExit(
          status: errno,
          reason: "waitpid-error"
        )
      )
      return true
    }
    return false
  }

  private func signalOwnedProcess(_ signal: Int32) throws {
    guard exit == nil, let processID else { return }
    guard Darwin.kill(processID, signal) == 0 || errno == ESRCH else {
      throw ProcessError.signalFailed(
        processID: processID,
        signal: signal,
        code: errno
      )
    }
  }

  private func record(_ exit: TrainingRunWorkerProcessExit) {
    guard self.exit == nil else { return }
    self.exit = exit
    monitorTask?.cancel()
    monitorTask = nil
    let pendingWaiters = waiters
    waiters.removeAll(keepingCapacity: false)
    for waiter in pendingWaiters {
      waiter.resume(returning: exit)
    }
  }

  private static func processExit(from waitStatus: Int32) -> TrainingRunWorkerProcessExit {
    let terminatingSignal = waitStatus & 0x7f
    if terminatingSignal == 0 {
      return TrainingRunWorkerProcessExit(
        status: (waitStatus >> 8) & 0xff,
        reason: "exit"
      )
    }
    return TrainingRunWorkerProcessExit(
      status: terminatingSignal,
      reason: "signal"
    )
  }

  private func spawn(
    executableURL: URL,
    arguments: [String],
    outputDescriptor: Int32,
    errorDescriptor: Int32
  ) throws -> pid_t {
    var fileActions: posix_spawn_file_actions_t?
    guard posix_spawn_file_actions_init(&fileActions) == 0 else {
      throw ProcessError.launchFailed(
        path: executableURL.path,
        reason: "posix spawn file-action initialization failed"
      )
    }
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    var attributes: posix_spawnattr_t?
    guard posix_spawnattr_init(&attributes) == 0 else {
      throw ProcessError.launchFailed(
        path: executableURL.path,
        reason: "posix spawn attribute initialization failed"
      )
    }
    defer { posix_spawnattr_destroy(&attributes) }

    var defaultSignals = sigset_t()
    var signalMask = sigset_t()
    sigemptyset(&defaultSignals)
    sigemptyset(&signalMask)
    for signal in [SIGINT, SIGTERM, SIGQUIT, SIGHUP, SIGPIPE] {
      sigaddset(&defaultSignals, signal)
    }
    let flags = Int16(
      POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
    )
    guard posix_spawnattr_setflags(&attributes, flags) == 0,
      posix_spawnattr_setsigdefault(&attributes, &defaultSignals) == 0,
      posix_spawnattr_setsigmask(&attributes, &signalMask) == 0,
      posix_spawn_file_actions_adddup2(&fileActions, outputDescriptor, STDOUT_FILENO) == 0,
      posix_spawn_file_actions_adddup2(&fileActions, errorDescriptor, STDERR_FILENO) == 0,
      posix_spawn_file_actions_addclose(&fileActions, outputDescriptor) == 0,
      posix_spawn_file_actions_addclose(&fileActions, errorDescriptor) == 0
    else {
      throw ProcessError.launchFailed(
        path: executableURL.path,
        reason: "posix spawn configuration failed"
      )
    }

    let argumentStorage = ([executableURL.path] + arguments).map { strdup($0) }
    guard argumentStorage.allSatisfy({ $0 != nil }) else {
      argumentStorage.forEach { free($0) }
      throw ProcessError.launchFailed(
        path: executableURL.path,
        reason: "argument allocation failed"
      )
    }
    defer { argumentStorage.forEach { free($0) } }
    var argumentPointers = argumentStorage
    argumentPointers.append(nil)
    var spawnedPID: pid_t = 0
    let result = executableURL.path.withCString { path in
      argumentPointers.withUnsafeMutableBufferPointer { buffer in
        posix_spawn(
          &spawnedPID,
          path,
          &fileActions,
          &attributes,
          buffer.baseAddress,
          environ
        )
      }
    }
    guard result == 0 else {
      throw ProcessError.launchFailed(
        path: executableURL.path,
        reason: "posix_spawn error=\(result)"
      )
    }
    return spawnedPID
  }

  private func appendDescriptor(for url: URL) throws -> Int32 {
    let descriptor = url.withUnsafeFileSystemRepresentation { path in
      guard let path else { return Int32(-1) }
      return Darwin.open(
        path,
        O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW,
        S_IRUSR | S_IWUSR
      )
    }
    guard descriptor >= 0 else {
      throw ProcessError.outputOpenFailed(path: url.path, code: errno)
    }
    do {
      try validateOutputDescriptor(descriptor, url: url)
    } catch {
      Darwin.close(descriptor)
      throw error
    }
    return descriptor
  }

  private func validateOutputDescriptor(_ descriptor: Int32, url: URL) throws {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else {
      throw ProcessError.outputInspectionFailed(path: url.path, code: errno)
    }
    guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
      throw ProcessError.unsafeOutput(path: url.path)
    }
    guard status.st_uid == geteuid() else {
      throw ProcessError.unexpectedOutputOwner(
        path: url.path,
        expected: geteuid(),
        actual: status.st_uid
      )
    }
    let permissions = status.st_mode & mode_t(0o777)
    guard permissions & mode_t(0o077) == 0 else {
      throw ProcessError.unsafeOutputPermissions(
        path: url.path,
        mode: UInt16(permissions)
      )
    }
    guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
      throw ProcessError.outputInspectionFailed(path: url.path, code: errno)
    }
  }
}
