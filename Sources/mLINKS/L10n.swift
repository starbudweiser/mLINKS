import Foundation

/// Texte traduit (fichiers Resources/*.lproj/Localizable.strings) ; langue du système, anglais sinon.
func L(_ key: String, _ args: CVarArg...) -> String {
    let text = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? text : String(format: text, arguments: args)
}
