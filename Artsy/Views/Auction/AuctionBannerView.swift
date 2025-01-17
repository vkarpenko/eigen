import UIKit
import Artsy_UIColors
import FLKAutoLayout
import SDWebImage

class AuctionBannerView: UIView {
    let viewModel: SaleViewModel

    // Note: These are in order as they'll be in the view hierarchy (ie: first in the list is at the back)
    private let backgroundImageView = UIImageView()
    private let darkeningView = DarkeningView()
    private let logoImageView = UIImageView()
    private let countdownView = ARCountdownView(color: .whiteColor())

    init(viewModel: SaleViewModel) {
        self.viewModel = viewModel
        super.init(frame: CGRect.zero)

        setupViews()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func willMoveToSuperview(newSuperview: UIView?) {
        super.willMoveToSuperview(newSuperview)

        // Countdown view only counts down when we have a superview.
        if let _ = newSuperview {
            countdownView.startTimer()
        } else {
            countdownView.stopTimer()
        }
    }
}

extension AuctionBannerView {
    private func setupViews() {

        // Configure views.
        countdownView.targetDate = viewModel.closingDate
        countdownView.heading = "Closing In"

        // Add all as subviews to self.
        [backgroundImageView, darkeningView, logoImageView, countdownView].forEach(apply(addSubview))

        // Background + darkening view always cover self totally.
        backgroundImageView.alignToView(self)
        darkeningView.alignToView(self)

        logoImageView.constrainHeight("70")

        // Device-specific layout for logo & countdown views.
        if traitCollection.horizontalSizeClass == .Regular {
            // Bottom lefthand corner with 40pt margin.
            logoImageView.alignLeadingEdgeWithView(self, predicate: "40")
            logoImageView.alignBottomEdgeWithView(self, predicate: "-40")

            // Must constraint self to 200pt tall on iPad, since our view hierarchy doesn't provide any height constraint and in its abses, defaults to the background image's height.
            constrainHeight("200")

            // Bottom righthand corner with 40pt margin.
            countdownView.alignTrailingEdgeWithView(self, predicate: "-40")
            countdownView.alignBottomEdgeWithView(self, predicate: "-40")
        } else {
            logoImageView.alignTopEdgeWithView(self, predicate: "30")
            countdownView.constrainTopSpaceToView(logoImageView, predicate: "7")
            countdownView.alignBottomEdgeWithView(self, predicate: "-30")

            // The background will stretch us to be larger (based on its image height), so we want to prevent that.
            backgroundImageView.setContentCompressionResistancePriority(UILayoutPriorityDefaultLow, forAxis: .Vertical)

            logoImageView.alignCenterXWithView(self, predicate: "0")
            countdownView.alignCenterXWithView(self, predicate: "0")
        }

        // Start any necessary image downloads.
        backgroundImageView.sd_setImageWithURL(viewModel.backgroundImageURL)
        logoImageView.sd_setImageWithURL(viewModel.profileImageURL) { [weak logoImageView] (image, _, _, _) in
            // This keeps the image view constrained to the image's aspect ratio, which allows us to 'left align' this on iPad.
            let aspectRatio = image.size.width / image.size.height
            logoImageView?.constrainAspectRatio("\(aspectRatio)")
        }
    }
}

private class DarkeningView: UIView {
    private override func didMoveToSuperview() {
        super.didMoveToSuperview()

        backgroundColor = UIColor(white: 0, alpha: 0.3)
    }
}
