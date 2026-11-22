import Foundation

/// マクロ(.smd)。1 行は「命令 下位命令と引数」で、下位命令はカンマで続けられる。
/// 命令と、それぞれが変える値:
/// - FrameSet: POS 左 上 幅 高さ(0.01 mm)・FRAMETYPE 番号(0 方眼 1 枠 2 片枠 3 軸)・LINEWIDTH 太さ・COLOR 色
/// - AxisSet: XSCALE〜RSCALE 最小 最大 [間隔 [分割数]](間隔を省くと自動)・XSCALETYPE〜RSCALETYPE
///   linear / log / Inverse / LogNormal / Inverse2・COLOR 主目盛の色 副目盛の色(4 つの軸とも)。
///   USCALE は X 軸の「共通」を、RSCALE は R 軸の「共通」を外す。LINEWIDTH は何も変えない
/// - Data: COLUMNX・COLUMNY 列(0 から)・PLOTTYPE・PLOTSIZE・COLOR(点の色)・LINETYPE・LINECOLOR・LINEWIDTH・LINEPITCH・
///   XTRANS / YTRANS(on・off・式)を覚えておき、Open ファイル名 でその値のデータを開く
/// - Insert: XTITLE 文字(枠の幅の半分・枠の下 16 mm、中寄せ)・YTITLE 文字(枠の左 8 mm・高さの半分、90 度回す)。
///   UTITLE・RTITLE・STRING は何も変えない
/// - DeleteGraph [All]・OpenSmp ファイル名・Print [off]・Refresh・Rem・Label 名前・Goto 名前・Pause
public struct MacroRunner {
    /// 外とのやりとり(ファイルを読む・印刷・止まったときに続けるか)
    public struct IO {
        public var readData: (String) -> DataFile?
        public var openSMP: (String) -> SMPProject?
        public var print: (_ showDialog: Bool) -> Void
        /// Pause の行で止まったとき。true なら続ける
        public var pause: (_ line: Int) -> Bool
        public init(readData: @escaping (String) -> DataFile?, openSMP: @escaping (String) -> SMPProject? = { _ in nil },
                    print: @escaping (Bool) -> Void = { _ in }, pause: @escaping (Int) -> Bool = { _ in true }) {
            self.readData = readData; self.openSMP = openSMP; self.print = print; self.pause = pause
        }
    }

    public enum Failure: Error, Equatable, LocalizedError {
        /// 読めない行(1 から数える)
        case error(line: Int)
        /// Pause で止めた行
        case stopped(line: Int)
        /// Goto が 1000 回を超えた(終わらないマクロ)
        case tooManyJumps(line: Int)

        public var errorDescription: String? {
            switch self {
            case .error(let l): return "\(l) 行目が読めません"
            case .stopped(let l): return "\(l) 行目で止めました"
            case .tooManyJumps(let l): return "\(l) 行目の Goto がくり返しすぎるので止めました"
            }
        }
    }

    /// Data の値(Open の前に決める)と、その既定
    struct DataState {
        var columnX = 0, columnY = 1
        var plotType = 2, plotSize = 300, color = 0
        var lineType = 0, lineColor = 0, lineWidth = 40, linePitch = 300
        var transformX = false, transformY = false
        var expressionX = "x", expressionY = "y"
    }

    public var project: SMPProject
    public var graphIndex: Int
    var data = DataState()

    public init(project: SMPProject, graphIndex: Int = 0) {
        self.project = project
        self.graphIndex = graphIndex
        if self.project.graphs.isEmpty { self.project.graphs = [Graph.makeDefault()] }
        self.graphIndex = Swift.max(0, Swift.min(graphIndex, self.project.graphs.count - 1))
    }

    /// マクロの文字(CP932 から直したもの)を実行する
    public mutating func run(_ text: String, io: IO) throws {
        let lines = Sma4TextEncoding.splitLines(text)
        var labels: [String: Int] = [:]
        for (i, l) in lines.enumerated() {
            let (cmd, rest) = MacroRunner.split(l)
            if cmd.lowercased() == "label" { labels[rest.trimmingCharacters(in: .whitespaces).lowercased()] = i }
        }
        var pc = 0
        var jumps = 0
        while pc < lines.count {
            let (cmd, rest) = MacroRunner.split(lines[pc])
            let lineNo = pc + 1
            pc += 1
            switch cmd.lowercased() {
            case "", "rem", "label", "refresh":
                continue
            case "goto":
                guard let target = labels[rest.trimmingCharacters(in: .whitespaces).lowercased()] else { throw Failure.error(line: lineNo) }
                jumps += 1
                if jumps > 1000 { throw Failure.tooManyJumps(line: lineNo) }
                pc = target + 1
            case "pause":
                if !io.pause(lineNo) { throw Failure.stopped(line: lineNo) }
            case "print":
                io.print(rest.trimmingCharacters(in: .whitespaces).lowercased() != "off")
            case "deletegraph":
                if rest.trimmingCharacters(in: .whitespaces).lowercased() == "all" {
                    project.graphs = [Graph.makeDefault()]
                    graphIndex = 0
                } else if !project.graphs.isEmpty {
                    project.graphs.remove(at: graphIndex)
                    if project.graphs.isEmpty { project.graphs = [Graph.makeDefault()] }
                    graphIndex = Swift.min(graphIndex, project.graphs.count - 1)
                }
                GraphOps.pruneData(&project)
            case "opensmp":
                guard let p = io.openSMP(rest.trimmingCharacters(in: .whitespaces)), !p.graphs.isEmpty else { throw Failure.error(line: lineNo) }
                for f in p.dataFiles.values where project.dataFile(named: f.name) == nil { project.setDataFile(f) }
                project.graphs.append(contentsOf: p.graphs)
                graphIndex = project.graphs.count - 1
            case "frameset", "axisset", "data", "insert":
                for part in rest.split(separator: ",", omittingEmptySubsequences: false) {
                    let sub = part.trimmingCharacters(in: .whitespaces)
                    guard !sub.isEmpty else { continue }
                    guard apply(cmd.lowercased(), sub, io: io) else { throw Failure.error(line: lineNo) }
                }
            default:
                throw Failure.error(line: lineNo)
            }
        }
    }

    /// 1 行を命令と残りに分ける
    static func split(_ line: String) -> (String, String) {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let sp = t.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return (t, "") }
        return (String(t[..<sp]), String(t[sp...]).trimmingCharacters(in: .whitespaces))
    }

    static func scaleType(_ word: String) -> ScaleType? {
        switch word.lowercased() {
        case "linear": return .linear
        case "log": return .logExponent
        case "inverse": return .inverseReciprocal
        case "lognormal": return .logNormal
        case "inverse2": return .inverseNormal
        default: return nil
        }
    }

    mutating func apply(_ cmd: String, _ sub: String, io: IO) -> Bool {
        let (word, arg) = MacroRunner.split(sub)
        let w = word.uppercased()
        let nums = arg.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { Double($0) }
        func int(_ k: Int) -> Int? { k < nums.count ? nums[k].map { Int($0) } : nil }
        func dbl(_ k: Int) -> Double? { k < nums.count ? nums[k] : nil }
        switch cmd {
        case "frameset":
            switch w {
            case "POS":
                guard let l = int(0), let t = int(1), let wd = int(2), let h = int(3) else { return false }
                project.graphs[graphIndex].left = l; project.graphs[graphIndex].top = t
                project.graphs[graphIndex].width = wd; project.graphs[graphIndex].height = h
            case "FRAMETYPE":
                guard let n = int(0), let f = FrameType(rawValue: n) else { return false }
                project.graphs[graphIndex].frameType = f
            case "LINEWIDTH":
                guard let n = int(0) else { return false }
                project.graphs[graphIndex].frameWidth = n
            case "COLOR":
                guard let n = int(0) else { return false }
                project.graphs[graphIndex].frameColor = SMPColor(colorref: n)
            default: return false
            }
        case "axisset":
            let axisOf: [String: Int] = ["X": 0, "Y": 1, "U": 2, "R": 3]
            if w.hasSuffix("SCALETYPE"), let i = axisOf[String(w.prefix(1))], w.count == 10 {
                guard let t = MacroRunner.scaleType(arg.trimmingCharacters(in: .whitespaces)) else { return false }
                project.graphs[graphIndex].axes[i].scaleType = t
            } else if w.hasSuffix("SCALE"), w.count == 6, let i = axisOf[String(w.prefix(1))] {
                guard let lo = dbl(0), let hi = dbl(1) else { return false }
                var a = project.graphs[graphIndex].axes[i]
                a.from = lo; a.to = hi
                if let inc = dbl(2) { a.increment = inc } else { a.autoStep = true }
                if let div = int(3) { a.division = Swift.max(div, 1) }
                project.graphs[graphIndex].axes[i] = a
                // U・R を決めると共通が外れる(U は X 軸の印、R は R 軸の印)
                if i == 2 { project.graphs[graphIndex].axes[0].commonWithOpposite = false }
                if i == 3 { project.graphs[graphIndex].axes[3].commonWithOpposite = false }
            } else if w == "COLOR" {
                guard let c1 = int(0) else { return false }
                let c2 = int(1) ?? c1
                for i in 0..<4 {
                    project.graphs[graphIndex].axes[i].major.color = SMPColor(colorref: c1)
                    project.graphs[graphIndex].axes[i].minor.color = SMPColor(colorref: c2)
                }
            } else if w == "LINEWIDTH" {
                guard int(0) != nil else { return false }   // 何も変えない
            } else {
                return false
            }
        case "data":
            switch w {
            case "OPEN":
                let path = arg.trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty, var file = io.readData(path) else { return false }
                let name = (path.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
                file.name = name
                project.setDataFile(file)
                var s = Series(name: name, path: path)
                s.columnX = data.columnX; s.columnY = data.columnY
                s.dotType = data.plotType; s.dotSize = data.plotSize; s.dotColor = SMPColor(colorref: data.color)
                s.lineType = LineType(code: data.lineType); s.lineColor = SMPColor(colorref: data.lineColor)
                s.lineWidth = data.lineWidth; s.pitch = data.linePitch
                s.transformX = data.transformX; s.transformY = data.transformY
                s.expressionX = data.expressionX; s.expressionY = data.expressionY
                s.curveDivisions = 0; s.lsqOrder = 0
                s.linesRead = 0
                project.graphs[graphIndex].series.append(s)
            case "COLUMNX": guard let n = int(0) else { return false }; data.columnX = n
            case "COLUMNY": guard let n = int(0) else { return false }; data.columnY = n
            case "PLOTTYPE": guard let n = int(0) else { return false }; data.plotType = n
            case "PLOTSIZE": guard let n = int(0) else { return false }; data.plotSize = n
            case "COLOR": guard let n = int(0) else { return false }; data.color = n
            case "LINETYPE": guard let n = int(0) else { return false }; data.lineType = n
            case "LINECOLOR": guard let n = int(0) else { return false }; data.lineColor = n
            case "LINEWIDTH": guard let n = int(0) else { return false }; data.lineWidth = n
            case "LINEPITCH": guard let n = int(0) else { return false }; data.linePitch = n
            case "XTRANS", "YTRANS":
                let v = arg.trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty else { return false }
                let isX = w == "XTRANS"
                switch v.lowercased() {
                case "on": if isX { data.transformX = true } else { data.transformY = true }
                case "off": if isX { data.transformX = false } else { data.transformY = false }
                default: if isX { data.expressionX = v } else { data.expressionY = v }
                }
            default: return false
            }
        case "insert":
            let g = project.graphs[graphIndex]
            func font(_ charSet: Int, _ face: String, angle: Bool) -> LogFont {
                LogFont(height: -2400, width: 0, escapement: angle ? -900 : 0, orientation: angle ? 900 : 0, weight: 400, italic: 0,
                        underline: 0, strikeOut: 0, charSet: charSet, outPrecision: 0, clipPrecision: 0, quality: 2,
                        pitchAndFamily: 18, faceName: face)
            }
            switch w {
            case "XTITLE", "YTITLE":
                var t = TextObject()
                let y = w == "YTITLE"
                t.kind = y ? .yTitle : .xTitle
                t.x = y ? -800 : g.width / 2
                t.y = y ? g.height / 2 : g.height + 1600
                t.alignment = 1
                t.text = arg
                t.latinFont = font(0, "Times New Roman", angle: y)
                t.japaneseFont = font(128, "ＭＳ 明朝", angle: y)
                t.symbolFont = font(2, "Symbol", angle: false)
                project.graphs[graphIndex].objects.append(ObjectItem(.text(t)))
            case "UTITLE", "RTITLE", "STRING":
                break   // 何も変えない
            default: return false
            }
        default:
            return false
        }
        return true
    }
}
