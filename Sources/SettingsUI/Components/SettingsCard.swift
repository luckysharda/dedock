import DesignSystem
import SwiftUI

/// An UPPERCASE section header over a grouped card (docs/design.md §7.2).
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: SettingsTokens.sectionHeaderSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: SettingsTokens.rowSpacing) { content }
                .padding(SettingsTokens.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SettingsTokens.cardRadius).fill(SettingsTokens.cardFill))
                .overlay(RoundedRectangle(cornerRadius: SettingsTokens.cardRadius).strokeBorder(SettingsTokens.cardStroke))
        }
    }
}

/// A labelled row: label on the left, control on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    var help: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let help { Text(help).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 16)
            control
        }
    }
}

/// A slider with a value field and unit, for timing and size values.
struct ValueSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let unit: String
    var help: String?

    var body: some View {
        SettingsRow(label: label, help: help) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 200)
                    .accessibilityLabel(label)
                TextField(label, value: $value, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .labelsHidden()
                    .onSubmit { value = min(range.upperBound, max(range.lowerBound, value)) }
                Text(unit).foregroundStyle(.secondary).frame(width: 22, alignment: .leading)
            }
        }
    }
}
