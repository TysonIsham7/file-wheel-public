import CoreGraphics
import Foundation
import PDFKit

public enum PDFToolSuffix {
    public static let ocr = "-ocr"
    public static let signed = "-signed"
    public static let protectedPDF = "-protected"
    public static let unlocked = "-unlocked"

    /// `Doc` stays `Doc-unlocked`. `Doc-protected` becomes `Doc-unlocked`.
    public static func unlockedBase(from baseName: String) -> String {
        var stem = baseName
        if stem.hasSuffix(protectedPDF) {
            stem = String(stem.dropLast(protectedPDF.count))
        }
        return stem + unlocked
    }
}

public enum PDFUnlock {
    public static let rejectedMessage = "The password was not accepted."
}

public enum PDFProtectValidation {
    public static let enterPassword = "Enter a password."
    public static let mismatch = "The passwords do not match."
    public static let enterCurrent = "Enter the current password."
}

public enum PasswordMemory {
    public static func clear(_ value: inout String) {
        if !value.isEmpty {
            value = String(repeating: "\u{0}", count: value.count)
        }
        value.removeAll(keepingCapacity: false)
    }
}

public enum PasswordPrompt {
    public static func shouldOfferUnlock(forFailure message: String, suppressForUnlockAttempt: Bool = false) -> Bool {
        guard message == ToolError.passwordProtected.message else { return false }
        return !suppressForUnlockAttempt
    }
}

public enum PDFLockProbe {
    public static func looksEncrypted(_ data: Data) -> Bool {
        data.range(of: Data("/Encrypt".utf8)) != nil
    }

    public static func throwIfLocked(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        if looksEncrypted(data) {
            throw ToolError.passwordProtected
        }
        if let document = PDFDocument(url: url), document.isLocked {
            throw ToolError.passwordProtected
        }
    }
}

public struct PDFProtectionOptions: Equatable, Sendable {
    public var userPassword: String
    public var ownerPassword: String
    public var allowPrinting: Bool
    public var allowCopying: Bool

    public init(userPassword: String, ownerPassword: String, allowPrinting: Bool, allowCopying: Bool) {
        self.userPassword = userPassword
        self.ownerPassword = ownerPassword
        self.allowPrinting = allowPrinting
        self.allowCopying = allowCopying
    }
}

public enum PDFEncryptionChoice {
    /// PDFKit is asked for a 256-bit key first. A failed write retries with PDFKit's own default.
    public static func keyLengthsToTry() -> [Int?] {
        [256, nil]
    }
}

public enum PDFProtectionPlan {
    public static func make(password: String, confirm: String, ownerPassword: String, allowPrinting: Bool, allowCopying: Bool) throws -> PDFProtectionOptions {
        if password.isEmpty {
            throw ToolError.message(PDFProtectValidation.enterPassword)
        }
        if password != confirm {
            throw ToolError.message(PDFProtectValidation.mismatch)
        }
        let owner = ownerPassword.isEmpty ? password : ownerPassword
        return PDFProtectionOptions(userPassword: password, ownerPassword: owner, allowPrinting: allowPrinting, allowCopying: allowCopying)
    }
}

public struct ProtectPDFParameters: Equatable, Sendable {
    public var password: String
    public var confirm: String
    public var ownerPassword: String
    public var allowPrinting: Bool
    public var allowCopying: Bool

    public init(password: String = "", confirm: String = "", ownerPassword: String = "", allowPrinting: Bool = true, allowCopying: Bool = true) {
        self.password = password
        self.confirm = confirm
        self.ownerPassword = ownerPassword
        self.allowPrinting = allowPrinting
        self.allowCopying = allowCopying
    }
}

public struct UnlockPDFParameters: Equatable, Sendable {
    public var password: String

    public init(password: String = "") {
        self.password = password
    }
}

public enum PDFLockAction: String, CaseIterable, Codable, Sendable, Equatable {
    case protect
    case unlock

    public var title: String {
        switch self {
        case .protect: return "Protect PDF"
        case .unlock: return "Unlock PDF"
        }
    }
}

enum PDFProtector {
    static func protect(source: URL, destination: URL, plan: PDFProtectionOptions) throws {
        var userPassword = plan.userPassword
        var ownerPassword = plan.ownerPassword
        defer {
            PasswordMemory.clear(&userPassword)
            PasswordMemory.clear(&ownerPassword)
        }
        guard let document = PDFDocument(url: source) else {
            throw ToolError.message("Could not read this PDF.")
        }
        let sourceBytes = try Data(contentsOf: source)
        if document.isLocked || PDFLockProbe.looksEncrypted(sourceBytes) {
            throw ToolError.passwordProtected
        }
        let permissions = accessPermissionMask(allowPrinting: plan.allowPrinting, allowCopying: plan.allowCopying)
        var wrote = false
        for keyLength in PDFEncryptionChoice.keyLengthsToTry() {
            let attempt = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-protect-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: attempt) }
            // This SDK exposes the write-option type as PDFDocumentWriteOption, not PDFDocument.WriteOption.
            var options: [PDFDocumentWriteOption: Any] = [
                PDFDocumentWriteOption.userPasswordOption: userPassword,
                PDFDocumentWriteOption.ownerPasswordOption: ownerPassword,
                PDFDocumentWriteOption.accessPermissionsOption: NSNumber(value: permissions)
            ]
            if let keyLength {
                let encryptionKey = PDFDocumentWriteOption(rawValue: kCGPDFContextEncryptionKeyLength as String)
                options[encryptionKey] = NSNumber(value: keyLength)
            }
            guard document.write(to: attempt, withOptions: options) else { continue }
            guard accepts(url: attempt, password: userPassword) else { continue }
            try AtomicFileWrite.commit(destination: destination) { temp in
                try FileManager.default.copyItem(at: attempt, to: temp)
            }
            wrote = true
            break
        }
        if !wrote {
            throw ToolError.message("Could not write the protected PDF.")
        }
    }

    static func unlock(source: URL, destination: URL, password: String) throws {
        var secret = password
        defer { PasswordMemory.clear(&secret) }
        if secret.isEmpty {
            throw ToolError.message(PDFProtectValidation.enterCurrent)
        }
        guard let document = PDFDocument(url: source) else {
            throw ToolError.message("Could not read this PDF.")
        }
        if document.isLocked {
            guard document.unlock(withPassword: secret) else {
                throw ToolError.message(PDFUnlock.rejectedMessage)
            }
        }
        // Writing the unlocked document in place keeps /Encrypt. Copy the pages into a new document.
        let decrypted = PDFDocument()
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) {
                decrypted.insert(page, at: decrypted.pageCount)
            }
        }
        if decrypted.pageCount == 0 {
            throw ToolError.message("Could not write the unlocked PDF.")
        }
        try AtomicFileWrite.commit(destination: destination) { temp in
            guard decrypted.write(to: temp) else {
                throw ToolError.message("Could not write the unlocked PDF.")
            }
        }
    }

    /// PDFKit's write option wants the permission bits as a number. This SDK's
    /// `PDFAccessPermissions` is not an `OptionSet`, so the cases are OR'd by raw value.
    /// Printing and copying stay off unless the panel toggles them on. The other
    /// permissions stay allowed.
    private static func accessPermissionMask(allowPrinting: Bool, allowCopying: Bool) -> UInt {
        var mask = permissionBit(.allowsDocumentChanges)
            | permissionBit(.allowsDocumentAssembly)
            | permissionBit(.allowsContentAccessibility)
            | permissionBit(.allowsCommenting)
            | permissionBit(.allowsFormFieldEntry)
        if allowPrinting {
            mask |= permissionBit(.allowsLowQualityPrinting)
            mask |= permissionBit(.allowsHighQualityPrinting)
        }
        if allowCopying {
            mask |= permissionBit(.allowsContentCopying)
        }
        return mask
    }

    private static func permissionBit(_ permission: PDFAccessPermissions) -> UInt {
        UInt(permission.rawValue)
    }

    private static func accepts(url: URL, password: String) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        if document.isLocked {
            return document.unlock(withPassword: password)
        }
        return document.pageCount > 0
    }
}
