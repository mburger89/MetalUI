// RED STUB (C10 lane 1): the API the tests compile against; every answer wrong.
enum ColorMath {
    struct RGB: Equatable { var red: Double; var green: Double; var blue: Double }
    struct RGBA: Equatable { var red: Double; var green: Double; var blue: Double; var opacity: Double }
    struct HSB: Equatable { var hue: Double; var saturation: Double; var brightness: Double }
    static func hsb(from rgb: RGB) -> HSB { HSB(hue: 0, saturation: 0, brightness: 0) }
    static func rgb(from hsb: HSB) -> RGB { RGB(red: 0, green: 0, blue: 0) }
    static func byte(_ value: Double) -> Int { 0 }
    static func hexString(_ color: RGBA, includesAlpha: Bool) -> String { "" }
    static func parseHex(_ text: String, allowsAlpha: Bool) -> RGBA? { nil }
    static func axComponents(_ color: RGBA) -> String { "" }
}
