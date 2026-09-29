import MetalUIScene

/// SKELETON.
public struct ImageBitmap: Sendable {
    let texture: ImageTexture

    public var width: Int { texture.width }
    public var height: Int { texture.height }

    public init(width: Int, height: Int, rgba: [UInt8]) {
        texture = ImageTexture(width: width, height: height, premultipliedRGBA: rgba)
    }

    #if canImport(ImageIO)
    public init?(contentsOfFile path: String) {
        return nil
    }
    #endif
}
