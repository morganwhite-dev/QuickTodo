// DecisionBoardComponents.swift
// Decision Pulse summarizes the workload without duplicating the selected task's
// recommendation, which belongs exclusively in the Next Move inspector.

import SwiftUI

struct DecisionPulseView: View {
    let activeCount: Int
    let readyCount: Int
    let riskCount: Int
    let completedCount: Int

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
                    Text("AT A GLANCE")
                        .tracking(1.2)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.accent)

                Text(pulseHeadline)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("A simple view of what needs your attention right now.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DecisionStat(label: "Active", value: "\(activeCount)", icon: "circle.grid.2x2", tint: Theme.general)
            DecisionStat(label: "Ready", value: "\(readyCount)", icon: "sparkles", tint: Theme.warning)
            DecisionStat(label: "Due soon", value: "\(riskCount)", icon: "exclamationmark.triangle", tint: Theme.critical)
            DecisionStat(label: "Completed", value: "\(completedCount)", icon: "checkmark", tint: Theme.lowPressure)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.panelBorder, lineWidth: 1)
        )
    }

    private var pulseHeadline: String {
        if riskCount > 0 { return "\(riskCount) task\(riskCount == 1 ? " is" : "s are") due soon" }
        if readyCount > 0 {
            return "\(readyCount) task\(readyCount == 1 ? " is" : "s are") ready to work on next"
        }
        return activeCount == 0
            ? "Nothing needs a decision right now"
            : "Your captured tasks are waiting to be planned"
    }

}

struct DecisionStat: View {
    let label: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.mutedText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 82, height: 72, alignment: .leading)
        .background(Color.white.opacity(0.032), in: RoundedRectangle(cornerRadius: 10))
    }
}
