import Foundation

enum Fixture {
    static func data(_ name: String) -> Data {
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") else {
            fatalError("Missing fixture \(name)")
        }
        return try! Data(contentsOf: url)
    }

    static func string(_ name: String) -> String {
        String(decoding: data(name), as: UTF8.self)
    }
}
