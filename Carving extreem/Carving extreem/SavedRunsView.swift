import SwiftUI

struct SavedRunsView: View {
    @ObservedObject var runStore: RunDataStore
    @State private var isTodayExpanded = true
    @State private var expandedYears: Set<Int> = []
    @State private var expandedMonths: Set<MonthKey> = []
    @State private var expandedDays: Set<DayKey> = []

    var body: some View {
        List {
            if !todayRuns.isEmpty {
                DisclosureGroup(isExpanded: $isTodayExpanded) {
                    ForEach(todayRuns) { run in
                        NavigationLink(destination: RunAnalysisView(run: run)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(run.name)
                                    .font(.headline)
                                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } label: {
                    Text("Today")
                }
            }
            ForEach(groupedRuns) { yearGroup in
                DisclosureGroup(isExpanded: binding(forYear: yearGroup.year)) {
                    ForEach(yearGroup.months) { monthGroup in
                        DisclosureGroup(isExpanded: binding(forMonth: monthGroup.key)) {
                            ForEach(monthGroup.days) { dayGroup in
                                DisclosureGroup(isExpanded: binding(forDay: dayGroup.key)) {
                                    ForEach(dayGroup.runs) { run in
                                        NavigationLink(destination: RunAnalysisView(run: run)) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(run.name)
                                                    .font(.headline)
                                                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.subheadline)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                } label: {
                                    Text(dayLabel(for: dayGroup.key))
                                }
                            }
                        } label: {
                            Text(monthLabel(for: monthGroup.key.month))
                        }
                    }
                } label: {
                    Text(String(yearGroup.year))
                }
            }
        }
        .navigationTitle("Saved runs")
        .onAppear {
            runStore.loadRuns()
        }
    }
}

private extension SavedRunsView {
    struct YearGroup: Identifiable {
        let id = UUID()
        let year: Int
        let months: [MonthGroup]
    }

    struct MonthGroup: Identifiable {
        let id = UUID()
        let key: MonthKey
        let days: [DayGroup]
    }

    struct DayGroup: Identifiable {
        let id = UUID()
        let key: DayKey
        let runs: [RunRecord]
    }

    struct MonthKey: Hashable {
        let year: Int
        let month: Int
    }

    struct DayKey: Hashable {
        let year: Int
        let month: Int
        let day: Int
    }

    var todayRuns: [RunRecord] {
        let calendar = Calendar.current
        return runStore.runs
            .filter { calendar.isDateInToday($0.date) }
            .sorted { $0.date > $1.date }
    }

    var groupedRuns: [YearGroup] {
        let calendar = Calendar.current
        let runsByYear = Dictionary(grouping: runStore.runs.filter { !calendar.isDateInToday($0.date) }) { run in
            calendar.component(.year, from: run.date)
        }
        return runsByYear.keys.sorted(by: >).map { year in
            let runsInYear = runsByYear[year] ?? []
            let runsByMonth = Dictionary(grouping: runsInYear) { run in
                calendar.component(.month, from: run.date)
            }
            let months = runsByMonth.keys.sorted(by: >).map { month in
                let runsInMonth = runsByMonth[month] ?? []
                let runsByDay = Dictionary(grouping: runsInMonth) { run in
                    calendar.component(.day, from: run.date)
                }
                let days = runsByDay.keys.sorted(by: >).map { day in
                    let runsInDay = (runsByDay[day] ?? []).sorted { $0.date > $1.date }
                    return DayGroup(key: DayKey(year: year, month: month, day: day), runs: runsInDay)
                }
                return MonthGroup(key: MonthKey(year: year, month: month), days: days)
            }
            return YearGroup(year: year, months: months)
        }
    }

    func binding(forYear year: Int) -> Binding<Bool> {
        Binding(
            get: { expandedYears.contains(year) },
            set: { isExpanded in
                if isExpanded {
                    expandedYears.insert(year)
                } else {
                    expandedYears.remove(year)
                }
            }
        )
    }

    func binding(forMonth key: MonthKey) -> Binding<Bool> {
        Binding(
            get: { expandedMonths.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedMonths.insert(key)
                } else {
                    expandedMonths.remove(key)
                }
            }
        )
    }

    func binding(forDay key: DayKey) -> Binding<Bool> {
        Binding(
            get: { expandedDays.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedDays.insert(key)
                } else {
                    expandedDays.remove(key)
                }
            }
        )
    }

    func monthLabel(for month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.monthSymbols[month - 1]
    }

    func dayLabel(for key: DayKey) -> String {
        let calendar = Calendar.current
        let components = DateComponents(year: key.year, month: key.month, day: key.day)
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(key.day)"
    }
}
