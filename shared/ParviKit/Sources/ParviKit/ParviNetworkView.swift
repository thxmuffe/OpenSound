import SwiftUI

struct ParviNetworkView: View {
    @ObservedObject var model: ChatModel
    @ViewState<Bool> private var showGraph = true
    @ViewState<String?> private var selected: String?
    @ViewState<[String: UnitPoint]> private var positions: [String: UnitPoint] = [:]
    @ViewState<Bool> private var confirmingRemoval = false
    @ViewState<String?> private var removalTarget: String?
    @ViewState<String?> private var removalSwarm: String?

    private var members: [NetworkNode] {
        model.network.nodes.sorted {
            if $0.id == model.node { return true }
            if $1.id == model.node { return false }
            return $0.id < $1.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Devices in this swarm").font(.headline)
                    Text("Observed connections among these members.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Swarm display", selection: $showGraph) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 90)
            }
            if showGraph { graph } else { memberList }
            if let member = members.first(where: { $0.id == selected }) {
                HStack(alignment: .top, spacing: 9) {
                    Circle().fill(member.statusColor).frame(width: 8, height: 8).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.displayName(member.id)) · \(member.statusLabel)").font(.callout.weight(.medium))
                        Text(member.id).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    Spacer()
                    if member.id != model.node {
                        Button("Remove both of us", role: .destructive) {
                            removalTarget = member.id
                            removalSwarm = model.selectedSwarmID
                            confirmingRemoval = true
                        }.disabled(!model.running || model.changingMembership)
                    }
                    Button { selected = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Close node details")
                }.padding(12).background(Color.parviCard, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 12) {
                legend("Running", .green)
                legend("Not responding", .yellow)
                legend("Disconnected", .red)
                legend("Checking", .gray)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(showGraph ? "Drag to arrange · select for details · connectivity, not audio routing" :
                    "Disconnected means unreachable, not necessarily stopped.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.padding(20)
        .alert("Remove both of us?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove both of us", role: .destructive) {
                if let swarm = removalSwarm, let target = removalTarget {
                    model.removeBoth(swarmID: swarm, target: target)
                }
            }
        } message: {
            Text("You and this device will leave this swarm, and both entry invitations will expire. Other swarm memberships are unaffected.")
        }
    }

    private var graph: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Path { path in
                    for edge in model.network.edges where edge.count == 2 {
                        if let a = members.firstIndex(where: { $0.id == edge[0] }),
                           let b = members.firstIndex(where: { $0.id == edge[1] }) {
                            path.move(to: point(a, size))
                            path.addLine(to: point(b, size))
                        }
                    }
                }.stroke(Color.teal.opacity(0.25), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .accessibilityHidden(true)
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    VStack(spacing: 6) {
                        Image(systemName: member.id == model.node ? "waveform.path" : "hifispeaker")
                            .font(.system(size: 22, weight: .light))
                            .frame(width: 58, height: 58)
                            .background(Color.parviBackground, in: Circle())
                            .overlay(Circle().strokeBorder(member.statusColor.opacity(0.7), lineWidth: selected == member.id ? 3 : 1.5))
                        Text(model.displayName(member.id)).font(.caption.weight(.medium)).lineLimit(1)
                        Text(member.statusLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(width: 116)
                    .contentShape(Rectangle())
                    .position(point(index, size))
                    .onTapGesture { selected = member.id }
                    .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("network")).onChanged { value in
                        guard size.width > 0, size.height > 0 else { return }
                        positions[member.id] = UnitPoint(x: min(max(value.location.x / size.width, 0.12), 0.88),
                                                        y: min(max(value.location.y / size.height, 0.2), 0.8))
                    }, including: .all)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(model.displayName(member.id)), \(member.statusLabel)")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { selected = member.id }
                }
                if members.isEmpty {
                    Text("Waiting for network observations…").font(.callout).foregroundStyle(.secondary)
                }
            }.coordinateSpace(name: "network")
        }
        .frame(minHeight: 160)
        .background(.teal.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.05)))
    }

    private var memberList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(members) { member in
                    Button { selected = member.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: member.id == model.node ? "waveform.path" : "hifispeaker")
                                .foregroundStyle(.teal).frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName(member.id)).font(.callout.weight(.medium))
                                Text(member.id).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Circle().fill(member.statusColor).frame(width: 7, height: 7)
                            Text(member.statusLabel).font(.caption).foregroundStyle(.secondary)
                        }.padding(12).background(Color.parviCard, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }.frame(maxHeight: .infinity)
    }

    private func point(_ index: Int, _ size: CGSize) -> CGPoint {
        let member = members[index]
        if let position = positions[member.id] {
            return CGPoint(x: position.x * size.width, y: position.y * size.height)
        }
        if members.count == 1 { return CGPoint(x: size.width / 2, y: size.height / 2) }
        if members.count == 2 {
            return CGPoint(x: size.width * (index == 0 ? 0.28 : 0.72), y: size.height / 2)
        }
        let angle = Double(index) / Double(members.count) * .pi * 2 - .pi / 2
        return CGPoint(x: size.width / 2 + cos(angle) * max(0, size.width / 2 - 70),
                       y: size.height / 2 + sin(angle) * max(0, size.height / 2 - 60))
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
