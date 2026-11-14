import SwiftUI

/// The conversion moment: the user sees the program their answers built,
/// day by day, with the first workout highlighted and any limit swaps shown.
/// They can swap any exercise before the first workout.
struct PlanRevealView: View {
    @State var program: UserProgram
    let profile: UserProfile
    var onStart: (UserProgram) -> Void
    var onBack: () -> Void

    @State private var swapTarget: SwapTarget?
    @State private var appeared = false

    struct SwapTarget: Identifiable {
        let dayKey: String
        let exerciseId: String
        var id: String { dayKey + exerciseId }
    }

    private var firstDayKey: String? {
        if let todayKey = Program.dayKey(for: Date()),
           program.day(forKey: todayKey) != nil {
            return todayKey
        }
        return program.days.first?.key
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your plan is ready")
                        .font(.largeTitle)
                        .bold()
                    Text(program.name)
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryText)
                    Text("Built from your answers — \(profile.goal.label.lowercased()), \(profile.daysPerWeek) days a week, \(profile.equipmentLabel.lowercased()).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 12)

                if !program.swaps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Swapped for you")
                            .font(.headline)
                        // Enumerated ids, not `\.from`: a program can
                        // swap the same exercise on two days, and
                        // duplicate ForEach ids break the list.
                        ForEach(Array(program.swaps.enumerated()), id: \.offset) { _, swap in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.triangle.swap")
                                    .foregroundStyle(Color.accentColor)
                                Text(swap.displayText)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .themeCard()
                }

                // Weekly plan overview (Leap pattern): each day with its
                // body area and estimated minutes, so the week reads at a
                // glance before the day-by-day detail.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your week")
                        .font(.headline)
                    Text("\(program.days.count) days · about \(program.days.reduce(0) { $0 + $1.estimatedMinutes }) min/week")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    ForEach(program.days) { day in
                        HStack {
                            Text(day.title)
                                .font(.subheadline)
                            Text("·")
                                .foregroundStyle(Theme.secondaryText)
                            Text(day.subtitle)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                            Spacer()
                            Text("~\(day.estimatedMinutes) min")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if !profile.targetAreas.isEmpty {
                        HStack(spacing: 6) {
                            Text("Focus:")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                            ForEach(Array(profile.targetAreas).sorted { $0.label < $1.label }, id: \.self) { area in
                                Text(area.label)
                                    .font(.caption)
                                    .bold()
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding()
                .themeCard()

                ForEach(Array(program.days.enumerated()), id: \.element.id) { index, day in
                    dayCard(day)
                        // Staggered entrance: the plan feels built for you,
                        // day by day, instead of all at once.
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(AppAnimation.page.delay(Double(index) * 0.04), value: appeared)
                }

                Button(action: { onStart(program) }) {
                    Text("Start my first workout")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: onBack) {
                    Text("← Back to my answers")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .onAppear { appeared = true }
        .sheet(item: $swapTarget) { target in
            swapSheet(for: target)
        }
    }

    private func dayCard(_ day: DayPlan) -> some View {
        let isFirst = day.key == firstDayKey
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(day.title)
                    .font(.headline)
                if isFirst {
                    Text("First workout")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
            Text(day.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            ForEach(day.exercises) { exercise in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("\(exercise.sets) × \(exercise.repRange)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button("Swap") {
                        swapTarget = SwapTarget(dayKey: day.key, exerciseId: exercise.id)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            if !day.finisher.isEmpty {
                Text("Finisher: " + day.finisher.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding()
        .background(isFirst ? Color.accentColor.opacity(0.08) : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFirst ? Color.accentColor : Theme.border, lineWidth: isFirst ? 2 : 1)
        )
    }

    private func swapSheet(for target: SwapTarget) -> some View {
        NavigationStack {
            let current = program.days.first { $0.key == target.dayKey }?
                .exercises.first { $0.id == target.exerciseId }
            let substitutes = ExerciseLibrary.byId(target.exerciseId)?.substitutes
                .compactMap { ExerciseLibrary.byId($0) }
                // Never offer an exercise a marked injury excludes as a
                // replacement — the picker must not undo the injury swap.
                .filter { InjuryAdaptation.excludedLimit(for: $0, limits: profile.limits) == nil } ?? []
            List {
                Group {
                Section {
                    if let current {
                        Text("Current: \(current.name) — \(current.sets) × \(current.repRange)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Section("Swap for") {
                    if substitutes.isEmpty {
                        Text("No substitutes for this exercise.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(substitutes) { lib in
                        Button {
                            applySwap(dayKey: target.dayKey, exerciseId: target.exerciseId, lib: lib)
                            swapTarget = nil
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lib.name).font(.headline)
                                Text("\(lib.muscle.label) · \(lib.equipment.map { $0.label }.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                }
                // Rows take the app's card color (set on the List itself it does nothing).
                .listRowBackground(Theme.card)
            }
            .pageListMargins()
            .oledList()
            .navigationTitle("Swap exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { swapTarget = nil }
                }
            }
        }
    }

    private func applySwap(dayKey: String, exerciseId: String, lib: LibraryExercise) {
        guard let dayIndex = program.days.firstIndex(where: { $0.key == dayKey }),
              let exIndex = program.days[dayIndex].exercises.firstIndex(where: { $0.id == exerciseId }) else {
            return
        }
        program.days[dayIndex].exercises[exIndex] = ProgramGenerator.template(for: lib, profile: profile)
    }
}
