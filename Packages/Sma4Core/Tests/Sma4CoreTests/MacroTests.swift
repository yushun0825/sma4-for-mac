import Foundation
import Testing
@testable import Sma4Core

/// マクロ: 命令ごとに変わる値
@Suite("マクロ")
struct MacroTests {
    func base() -> SMPProject {
        var p = SMPProject()
        var g = Graph.makeDefault()
        g.left = 4000; g.top = 1500; g.width = 14000; g.height = 10000
        for i in 0..<4 { g.axes[i].from = 0; g.axes[i].to = 10; g.axes[i].increment = 2; g.axes[i].autoStep = false }
        p.graphs = [g]
        return p
    }
    let files: [String: DataFile] = [
        "C:\\sma4test\\t4\\mdat1.dat": DataFile(name: "mdat1.dat", lines: ["1 1", "2 4", "3 9", "4 16"]),
        "C:\\sma4test\\t4\\mdat2.dat": DataFile(name: "mdat2.dat", lines: ["1 2 3", "2 3 5", "3 4 7"]),
    ]
    func run(_ text: String) throws -> (SMPProject, [String]) {
        var m = MacroRunner(project: base())
        try m.run(text, io: .init(readData: { files[$0] }))
        let lines = SMPWriter.text(for: m.project, now: Date(timeIntervalSince1970: 0)).components(separatedBy: "\r\n")
        return (m.project, lines)
    }

    @Test func frameAndAxis() throws {
        let (p, l) = try run("""
        Rem frame and axis
        FrameSet POS 3000 2500 9000 7000
        FrameSet FRAMETYPE 2
        FrameSet LINEWIDTH 60,COLOR 255
        AxisSet XSCALE 0 5 1 2
        AxisSet YSCALE 1 1000 1 10,YSCALETYPE LogNormal
        AxisSet LINEWIDTH 30 20
        AxisSet COLOR 16711680 65280
        """)
        let gi = try #require(l.firstIndex(of: "[GRAPH]"))
        #expect(l[gi + 1] == "3000 2500 9000 7000" && l[gi + 2] == "100 2 0 0 1 0" && l[gi + 3] == "60 255 0 16777215")
        let x = try #require(l.firstIndex(of: "[AXIS-0]"))
        #expect(l[x + 1].hasPrefix("0.000000e+00 5.000000e+00 1.000000e+00 "))
        let y = try #require(l.firstIndex(of: "[AXIS-1]"))
        #expect(l[y + 1].hasPrefix("1.000000e+00 1.000000e+03 1.000000e+00 ") && l[y + 2].hasPrefix("10 3 0 1 "))
        #expect(p.graphs[0].axes.allSatisfy { $0.major.color.colorref == 16711680 && $0.minor.color.colorref == 65280 })
        #expect(p.graphs[0].axes.allSatisfy { $0.major.width == 40 })   // LINEWIDTH は何も変えない
    }

    @Test func scaleWithoutIncrementAndUR() throws {
        let (p, _) = try run("AxisSet XSCALE 0 8\nAxisSet XSCALETYPE log\nAxisSet RSCALE 0 50 10 5,RSCALETYPE Inverse2,USCALE 1 2,USCALETYPE Inverse")
        let a = p.graphs[0].axes
        #expect(a[0].to == 8 && a[0].increment == 2 && a[0].autoStep && a[0].scaleType == .logExponent)
        #expect(!a[0].commonWithOpposite && a[1].commonWithOpposite && !a[3].commonWithOpposite)
        #expect(a[2].from == 1 && a[2].to == 2 && a[2].autoStep && a[2].scaleType == .inverseReciprocal)
        #expect(a[3].from == 0 && a[3].to == 50 && a[3].increment == 10 && a[3].division == 5 && a[3].scaleType == .inverseNormal)
    }

    @Test func dataOpen() throws {
        let (p, l) = try run("""
        Data PLOTTYPE 4,PLOTSIZE 400,COLOR 255,LINETYPE 2,LINECOLOR 65280,LINEWIDTH 50,LINEPITCH 200,COLUMNX 1,COLUMNY 2,YTRANS y*2,Open C:\\sma4test\\t4\\mdat1.dat
        Data XTRANS on,YTRANS on,XTRANS x+1,YTRANS y*3,COLUMNX 0,COLUMNY 1,Open C:\\sma4test\\t4\\mdat2.dat
        """)
        #expect(p.graphs[0].series.count == 2)
        let i = try #require(l.firstIndex(of: "[mdat1.dat]"))
        #expect(Array(l[i...(i + 11)]) == ["[mdat1.dat]", "C:\\sma4test\\t4\\mdat1.dat", "0 0 0 0 1 2 0 0 -1 ", "50 65280 200 0 0 0 0",
                                           "2 4 400 255", "0 0 1 0 0 0 16777215 5", "0 0 0", "x", "y*2",
                                           "0 0 0 0 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00 0.000000e+00", "1 40 0 300 1", ""])
        let j = try #require(l.firstIndex(of: "[mdat2.dat]"))
        #expect(l[j + 6] == "1 1 0" && l[j + 7] == "x+1" && l[j + 8] == "y*3")
        #expect(p.dataFile(named: "mdat1.dat")?.lines == ["1 1", "2 4", "3 9", "4 16"])
    }

    @Test func titles() throws {
        let (_, l) = try run("Insert XTITLE Time / s\nInsert YTITLE Value\nInsert UTITLE x\nInsert STRING hello")
        let o = try #require(l.firstIndex(of: "[LEGEND]"))
        #expect(Array(l[(o + 1)...(o + 12)]) == ["2", "4", "7000 11600 0 1 1 0", "Time / s", "-2400 0 0 0 400 0 0 0 0 0 0 2 18", "Times New Roman",
                                                  "-2400 0 0 0 400 0 0 0 128 0 0 2 18", "ＭＳ 明朝", "-2400 0 0 0 400 0 0 0 2 0 0 2 18", "Symbol", "", "5"])
        #expect(l[o + 13] == "-800 5000 0 1 1 0" && l[o + 15] == "-2400 0 -900 900 400 0 0 0 0 0 0 2 18")
    }

    @Test func controlFlowAndErrors() throws {
        var m = MacroRunner(project: base())
        var paused: [Int] = []
        try m.run("Label top\nFrameSet LINEWIDTH 70\nPause\nRem done", io: .init(readData: { _ in nil }, pause: { paused.append($0); return true }))
        #expect(paused == [3] && m.project.graphs[0].frameWidth == 70)
        #expect(throws: MacroRunner.Failure.stopped(line: 1)) { try m.run("Pause", io: .init(readData: { _ in nil }, pause: { _ in false })) }
        #expect(throws: MacroRunner.Failure.error(line: 2)) { try m.run("Rem\nFoo 1", io: .init(readData: { _ in nil })) }
        #expect(throws: MacroRunner.Failure.error(line: 1)) { try m.run("Data Open missing.dat", io: .init(readData: { _ in nil })) }
        #expect(throws: MacroRunner.Failure.tooManyJumps(line: 2)) { try m.run("Label a\nGoto a", io: .init(readData: { _ in nil })) }
        var n = MacroRunner(project: base())
        try n.run("Goto skip\nFrameSet LINEWIDTH 99\nLabel skip\nDeleteGraph All", io: .init(readData: { _ in nil }))
        #expect(n.project.graphs.count == 1 && n.project.graphs[0].frameWidth != 99)
    }
}
