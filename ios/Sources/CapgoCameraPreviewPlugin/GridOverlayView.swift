import UIKit

class GridOverlayView: UIView {

    var gridMode: String = "none" {
        didSet {
            isHidden = gridMode == "none"
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.clear
        isUserInteractionEnabled = false
        isHidden = true
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        if gridMode == "none" {
            return
        }

        context.setStrokeColor(UIColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1.0)

        if gridMode == "3x3" {
            drawGrid(context: context, rect: rect, divisions: 3)
        } else if gridMode == "4x4" {
            drawGrid(context: context, rect: rect, divisions: 4)
        }
    }

    private func drawGrid(context: CGContext, rect: CGRect, divisions: Int) {
        let stepX = rect.width / CGFloat(divisions)
        let stepY = rect.height / CGFloat(divisions)

        // Draw vertical lines
        for i in 1..<divisions {
            let x = CGFloat(i) * stepX
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: rect.height))
        }

        // Draw horizontal lines
        for i in 1..<divisions {
            let y = CGFloat(i) * stepY
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.width, y: y))
        }

        context.strokePath()
    }
}
