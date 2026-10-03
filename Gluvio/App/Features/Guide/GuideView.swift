import GlucoseCore
import SwiftUI

struct GuideView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PlateMethodView()
                    } label: {
                        Label("The plate method", systemImage: "circle.grid.cross")
                    }
                }
                Section("Simple swaps") {
                    ForEach(GuideContent.swaps) { swap in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(swap.instead).strikethrough().foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption)
                                Text(swap.tryThis).fontWeight(.medium)
                            }
                            Text(swap.why).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Instead of \(swap.instead), try \(swap.tryThis). \(swap.why)")
                    }
                }
                Section {
                    ForEach(GuideContent.exercise) { idea in
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idea.title).fontWeight(.medium)
                                Text(idea.detail).font(.callout).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: idea.systemImage).foregroundStyle(.tint)
                        }
                    }
                } header: {
                    Text("Moving more")
                } footer: {
                    Text(GuideContent.exerciseCaution)
                }
                Section {
                    DisclaimerFooter()
                }
            }
            .navigationTitle("Guide")
        }
    }
}

struct PlateMethodView: View {
    private let colors: [Color] = [.green, .red.opacity(0.8), .orange]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PlateDiagram(colors: colors)
                    .frame(width: 240, height: 240)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Plate divided into half vegetables, a quarter protein and a quarter carbohydrate foods")
                ForEach(Array(GuideContent.plate.enumerated()), id: \.offset) { index, section in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 4).fill(colors[index]).frame(width: 16, height: 16).padding(.top, 3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(section.title) · \(Int(section.share * 100))%").font(.headline)
                            Text(section.examples).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(GuideContent.plateTip)
                DisclaimerFooter()
            }
            .padding()
        }
        .navigationTitle("The plate method")
    }
}

/// Half vegetables (left), a quarter protein, a quarter carbohydrate foods.
struct PlateDiagram: View {
    var colors: [Color]

    var body: some View {
        ZStack {
            Circle().fill(Color(uiColor: .systemGray5))
            Wedge(start: .degrees(90), end: .degrees(270)).fill(colors[0]).padding(14)
            Wedge(start: .degrees(270), end: .degrees(360)).fill(colors[1]).padding(14)
            Wedge(start: .degrees(0), end: .degrees(90)).fill(colors[2]).padding(14)
            Text("½").font(.largeTitle.bold()).foregroundStyle(.white).offset(x: -55)
            Text("¼").font(.title.bold()).foregroundStyle(.white).offset(x: 45, y: -45)
            Text("¼").font(.title.bold()).foregroundStyle(.white).offset(x: 45, y: 45)
        }
    }
}

struct Wedge: Shape {
    var start: Angle
    var end: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2, startAngle: start, endAngle: end, clockwise: false)
        path.closeSubpath()
        return path
    }
}
