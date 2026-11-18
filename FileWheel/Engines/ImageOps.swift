import Foundation

public enum ImageOps {
    public static func crop(_ image: RasterImage, to rect: FWRect) throws -> RasterImage {
        let integral = rect.integral()
        let x = Int(integral.x)
        let y = Int(integral.y)
        let width = Int(integral.width)
        let height = Int(integral.height)
        guard width > 0, height > 0, x >= 0, y >= 0, x + width <= image.width, y + height <= image.height else {
            throw ToolError.message("The crop rectangle does not fit the image.")
        }
        var output = RasterImage(width: width, height: height, fill: .black)
        for row in 0..<height {
            let source = ((y + row) * image.width + x) * 4
            let dest = row * width * 4
            output.rgba.replaceSubrange(dest..<(dest + width * 4), with: image.rgba[source..<(source + width * 4)])
        }
        return output
    }

    public static func adjust(_ image: RasterImage, exposure: Double, contrast: Double, saturation: Double, sharpness: Double, rotation: Int, flipHorizontal: Bool, flipVertical: Bool) -> RasterImage {
        var working = image
        if abs(sharpness) > 0.001 {
            working = sharpen(working, amount: sharpness)
        }
        var adjusted = RasterImage(width: working.width, height: working.height, fill: .black)
        let exposureFactor = pow(2.0, exposure)
        let contrastFactor = max(0, contrast)
        for y in 0..<working.height {
            for x in 0..<working.width {
                let pixel = working.pixel(x, y)
                var channels = [Double(pixel.r), Double(pixel.g), Double(pixel.b)].map { value in
                    var sample = value / 255.0
                    sample *= exposureFactor
                    sample = (sample - 0.5) * contrastFactor + 0.5
                    return sample
                }
                let luma = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
                for index in 0..<3 {
                    channels[index] = luma + (channels[index] - luma) * saturation
                }
                adjusted.setPixel(x, y, RGBA(
                    r: byte(channels[0]),
                    g: byte(channels[1]),
                    b: byte(channels[2]),
                    a: pixel.a
                ))
            }
        }
        adjusted = rotate(adjusted, degrees: rotation)
        if flipHorizontal {
            adjusted = flip(adjusted, horizontal: true)
        }
        if flipVertical {
            adjusted = flip(adjusted, horizontal: false)
        }
        return adjusted
    }

    public static func fill(_ image: inout RasterImage, rect: FWRect, color: RGBA) {
        let integral = rect.integral()
        let minX = max(0, Int(integral.x))
        let minY = max(0, Int(integral.y))
        let maxX = min(image.width, Int(integral.maxX))
        let maxY = min(image.height, Int(integral.maxY))
        guard maxX > minX, maxY > minY else { return }
        for y in minY..<maxY {
            for x in minX..<maxX {
                image.setPixel(x, y, color)
            }
        }
    }

    public static func strokeRect(_ image: inout RasterImage, rect: FWRect, color: RGBA, width: Int) {
        let integral = rect.integral()
        let thickness = max(1, width)
        for offset in 0..<thickness {
            let inset = FWRect(
                x: integral.x + Double(offset),
                y: integral.y + Double(offset),
                width: max(1, integral.width - Double(offset * 2)),
                height: max(1, integral.height - Double(offset * 2))
            )
            line(image: &image, from: FWPoint(x: inset.x, y: inset.y), to: FWPoint(x: inset.maxX, y: inset.y), color: color)
            line(image: &image, from: FWPoint(x: inset.maxX, y: inset.y), to: FWPoint(x: inset.maxX, y: inset.maxY), color: color)
            line(image: &image, from: FWPoint(x: inset.maxX, y: inset.maxY), to: FWPoint(x: inset.x, y: inset.maxY), color: color)
            line(image: &image, from: FWPoint(x: inset.x, y: inset.maxY), to: FWPoint(x: inset.x, y: inset.y), color: color)
        }
    }

    public static func line(image: inout RasterImage, from start: FWPoint, to end: FWPoint, color: RGBA, thickness: Int = 1) {
        let steps = max(1, Int(hypot(end.x - start.x, end.y - start.y)))
        let radius = max(0, thickness / 2)
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let x = Int(start.x + (end.x - start.x) * t)
            let y = Int(start.y + (end.y - start.y) * t)
            for oy in -radius...radius {
                for ox in -radius...radius {
                    image.setPixel(x + ox, y + oy, color)
                }
            }
        }
    }

    public static func arrow(image: inout RasterImage, from start: FWPoint, to end: FWPoint, color: RGBA) {
        line(image: &image, from: start, to: end, color: color, thickness: 2)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: Double = 12
        let left = FWPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6))
        let right = FWPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6))
        line(image: &image, from: end, to: left, color: color, thickness: 2)
        line(image: &image, from: end, to: right, color: color, thickness: 2)
    }

    public static func drawText(_ image: inout RasterImage, text: String, origin: FWPoint, size: Double, color: RGBA) {
        let scale = max(1, Int(size / 7))
        var cursor = Int(origin.x)
        let top = Int(origin.y)
        for character in text {
            let glyph = BitmapFont.glyph(character)
            for row in 0..<glyph.count {
                for column in 0..<glyph[row].count where glyph[row][column] == 1 {
                    for sy in 0..<scale {
                        for sx in 0..<scale {
                            image.setPixel(cursor + column * scale + sx, top + row * scale + sy, color)
                        }
                    }
                }
            }
            cursor += (5 + 1) * scale
        }
    }

    public static func collage(images: [RasterImage], layout: CollageLayout, gap: Int, background: RGBA, cell: Int = 128) -> RasterImage {
        let columns: Int
        let rows: Int
        switch layout {
        case .grid2x2:
            columns = 2
            rows = 2
        case .grid3x3:
            columns = 3
            rows = 3
        case .horizontal:
            columns = max(1, images.count)
            rows = 1
        case .vertical:
            columns = 1
            rows = max(1, images.count)
        }
        let width = columns * cell + (columns + 1) * gap
        let height = rows * cell + (rows + 1) * gap
        var canvas = RasterImage(width: width, height: height, fill: background)
        for index in 0..<min(images.count, columns * rows) {
            let column = index % columns
            let row = index / columns
            let frame = FWRect(
                x: Double(gap + column * (cell + gap)),
                y: Double(gap + row * (cell + gap)),
                width: Double(cell),
                height: Double(cell)
            )
            blit(images[index], into: &canvas, frame: frame)
        }
        return canvas
    }

    public static func scale(_ image: RasterImage, to width: Int, height: Int) -> RasterImage {
        guard width > 0, height > 0, image.width > 0, image.height > 0 else {
            return RasterImage(width: max(1, width), height: max(1, height), fill: .black)
        }
        var output = RasterImage(width: width, height: height, fill: .black)
        for y in 0..<height {
            let sourceY = min(image.height - 1, y * image.height / height)
            for x in 0..<width {
                let sourceX = min(image.width - 1, x * image.width / width)
                output.setPixel(x, y, image.pixel(sourceX, sourceY))
            }
        }
        return output
    }

    private static func blit(_ image: RasterImage, into canvas: inout RasterImage, frame: FWRect) {
        let fitted = PageLayout.fit(image: FWSize(width: Double(image.width), height: Double(image.height)), page: FWSize(width: frame.width, height: frame.height))
        let scaled = scale(image, to: max(1, Int(fitted.width)), height: max(1, Int(fitted.height)))
        let originX = Int(frame.x + fitted.x)
        let originY = Int(frame.y + fitted.y)
        for y in 0..<scaled.height {
            for x in 0..<scaled.width {
                canvas.setPixel(originX + x, originY + y, scaled.pixel(x, y))
            }
        }
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, Int(value * 255.0 + 0.5))))
    }

    private static func sharpen(_ image: RasterImage, amount: Double) -> RasterImage {
        var output = image
        let strength = min(2, max(0, amount))
        for y in 1..<(image.height - 1) {
            for x in 1..<(image.width - 1) {
                let center = image.pixel(x, y)
                let up = image.pixel(x, y - 1)
                let down = image.pixel(x, y + 1)
                let left = image.pixel(x - 1, y)
                let right = image.pixel(x + 1, y)
                func channel(_ c: (RGBA) -> UInt8) -> UInt8 {
                    let value = Double(c(center)) + strength * (4 * Double(c(center)) - Double(c(up)) - Double(c(down)) - Double(c(left)) - Double(c(right)))
                    return UInt8(min(255, max(0, Int(value.rounded()))))
                }
                output.setPixel(x, y, RGBA(r: channel(\.r), g: channel(\.g), b: channel(\.b), a: center.a))
            }
        }
        return output
    }

    private static func rotate(_ image: RasterImage, degrees: Int) -> RasterImage {
        let turns = ((degrees % 360) + 360) % 360
        switch turns {
        case 90:
            var output = RasterImage(width: image.height, height: image.width, fill: .black)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    output.setPixel(image.height - 1 - y, x, image.pixel(x, y))
                }
            }
            return output
        case 180:
            var output = RasterImage(width: image.width, height: image.height, fill: .black)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    output.setPixel(image.width - 1 - x, image.height - 1 - y, image.pixel(x, y))
                }
            }
            return output
        case 270:
            var output = RasterImage(width: image.height, height: image.width, fill: .black)
            for y in 0..<image.height {
                for x in 0..<image.width {
                    output.setPixel(y, image.width - 1 - x, image.pixel(x, y))
                }
            }
            return output
        default:
            return image
        }
    }

    private static func flip(_ image: RasterImage, horizontal: Bool) -> RasterImage {
        var output = RasterImage(width: image.width, height: image.height, fill: .black)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let dx = horizontal ? image.width - 1 - x : x
                let dy = horizontal ? y : image.height - 1 - y
                output.setPixel(dx, dy, image.pixel(x, y))
            }
        }
        return output
    }
}

enum BitmapFont {
    static func glyph(_ character: Character) -> [[Int]] {
        let maps: [Character: [[Int]]] = [
            "A": [[0,1,1,1,0],[1,0,0,0,1],[1,1,1,1,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1]],
            "E": [[1,1,1,1,1],[1,0,0,0,0],[1,0,0,0,0],[1,1,1,1,0],[1,0,0,0,0],[1,0,0,0,0],[1,1,1,1,1]],
            " ": [[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0]]
        ]
        if let glyph = maps[character] ?? maps[Character(character.uppercased())] {
            return glyph
        }
        return [[1,1,1,1,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,1]]
    }
}
