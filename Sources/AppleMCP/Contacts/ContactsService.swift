import Contacts
import Foundation

enum ContactsError: Error, CustomStringConvertible {
    case accessDenied
    case saveFailed(String)

    var description: String {
        switch self {
        case .accessDenied:
            return "Contacts access denied. Grant access in System Settings → Privacy & Security → Contacts."
        case .saveFailed(let s):
            return "Failed to save contact: \(s)"
        }
    }
}

private struct PostalRow: Sendable {
    let label: String
    let formatted: String
    let street: String
    let city: String
    let state: String
    let postalCode: String
    let country: String
}

private struct ContactRow: Sendable {
    let id: String
    let givenName: String
    let familyName: String
    let nickname: String
    let organization: String
    let phones: [(label: String, value: String)]
    let emails: [(label: String, value: String)]
    let urls: [(label: String, value: String)]
    let postalAddresses: [PostalRow]
    let birthday: String?

    init(_ c: CNContact) {
        id = c.identifier
        givenName = c.givenName
        familyName = c.familyName
        nickname = c.nickname
        organization = c.organizationName
        phones = c.phoneNumbers.map { p in
            (label: CNLabeledValue<NSString>.localizedString(forLabel: p.label ?? ""),
             value: p.value.stringValue)
        }
        emails = c.emailAddresses.map { e in
            (label: CNLabeledValue<NSString>.localizedString(forLabel: e.label ?? ""),
             value: e.value as String)
        }
        urls = c.urlAddresses.map { u in
            (label: CNLabeledValue<NSString>.localizedString(forLabel: u.label ?? ""),
             value: u.value as String)
        }
        postalAddresses = c.postalAddresses.map { addr in
            let label = CNLabeledValue<NSString>.localizedString(forLabel: addr.label ?? "")
            let formatted = CNPostalAddressFormatter.string(from: addr.value, style: .mailingAddress)
            return PostalRow(
                label: label,
                formatted: formatted,
                street: addr.value.street,
                city: addr.value.city,
                state: addr.value.state,
                postalCode: addr.value.postalCode,
                country: addr.value.country
            )
        }
        if let b = c.birthday {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            if b.year != nil, b.year != 0 {
                f.dateFormat = "yyyy-MM-dd"
            } else {
                f.dateFormat = "--MM-dd"
            }
            if let d = Calendar(identifier: .gregorian).date(from: b) {
                birthday = f.string(from: d)
            } else {
                birthday = nil
            }
        } else {
            birthday = nil
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "given_name": givenName,
            "family_name": familyName,
            "full_name": [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        ]
        if !nickname.isEmpty { dict["nickname"] = nickname }
        if !organization.isEmpty { dict["organization"] = organization }
        if !phones.isEmpty {
            dict["phones"] = phones.map { ["label": $0.label, "number": $0.value] }
        }
        if !emails.isEmpty {
            dict["emails"] = emails.map { ["label": $0.label, "address": $0.value] }
        }
        if !urls.isEmpty {
            dict["urls"] = urls.map { ["label": $0.label, "url": $0.value] }
        }
        if !postalAddresses.isEmpty {
            dict["addresses"] = postalAddresses.map { a -> [String: String] in
                [
                    "label": a.label,
                    "formatted": a.formatted,
                    "street": a.street,
                    "city": a.city,
                    "state": a.state,
                    "postal_code": a.postalCode,
                    "country": a.country
                ]
            }
        }
        if let b = birthday { dict["birthday"] = b }
        return dict
    }
}

enum ContactsService {
    private static var keysToFetch: [CNKeyDescriptor] {
        [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor
        ]
    }

    private static func requestAccess(_ store: CNContactStore) async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = try await store.requestAccess(for: .contacts)
            if !granted { throw ContactsError.accessDenied }
        default:
            throw ContactsError.accessDenied
        }
    }

    static func search(query: String, limit: Int) async throws -> [[String: Any]] {
        let store = CNContactStore()
        try await requestAccess(store)

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        var rows: [ContactRow] = []

        if trimmed.contains("@") {
            let predicate = CNContact.predicateForContacts(matchingEmailAddress: trimmed)
            let matches = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            rows = matches.map(ContactRow.init)
        } else if looksLikePhone(trimmed) {
            let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: trimmed))
            let matches = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            rows = matches.map(ContactRow.init)
        }

        if rows.isEmpty {
            let namePredicate = CNContact.predicateForContacts(matchingName: trimmed)
            let nameMatches = try store.unifiedContacts(matching: namePredicate, keysToFetch: keysToFetch)
            rows = nameMatches.map(ContactRow.init)
        }

        // Fallback substring scan if still empty: walk the whole address book.
        if rows.isEmpty {
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            var collected: [ContactRow] = []
            try store.enumerateContacts(with: request) { contact, stop in
                let haystack = (contact.givenName + " " + contact.familyName + " " +
                                contact.nickname + " " + contact.organizationName).lowercased()
                if haystack.contains(lowered) {
                    collected.append(ContactRow(contact))
                    if collected.count >= limit { stop.pointee = true }
                }
            }
            rows = collected
        }

        return rows.prefix(limit).map { $0.toDictionary() }
    }

    static func createContact(givenName: String?,
                              familyName: String?,
                              organization: String?,
                              phones: [String],
                              emails: [String]) async throws -> [String: Any] {
        let store = CNContactStore()
        try await requestAccess(store)

        let contact = CNMutableContact()
        if let g = givenName { contact.givenName = g }
        if let f = familyName { contact.familyName = f }
        if let o = organization { contact.organizationName = o }
        contact.phoneNumbers = phones.map {
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
        }
        contact.emailAddresses = emails.map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        do {
            try store.execute(saveRequest)
        } catch {
            throw ContactsError.saveFailed(error.localizedDescription)
        }
        return ContactRow(contact).toDictionary()
    }

    private static func looksLikePhone(_ s: String) -> Bool {
        let digits = s.filter { $0.isNumber }
        guard digits.count >= 5 else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789+()- ")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
