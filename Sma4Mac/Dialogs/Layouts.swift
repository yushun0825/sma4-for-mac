import Foundation

/// ダイアログの配置と文言(Sma4 for Mac で作ったもの)。
/// 部品の ID は Dialogs/*.swift の処理と合わせてある(ID を変えるときは両方を直す)。
extension DlgTemplate {
    // MARK: - 軸(タブ 3 枚)

    static let axisScale = DlgLayout.dialog(width: 210) { d in
        d.row(nil, .check(524, "この軸を描く"))
        d.space(3)
        d.labels("始まり", "終わり", "目盛の間隔", "副目盛の分割数")
        d.row("始まり", .field(513, w: 64))
        d.row("終わり", .field(514, w: 64))
        d.row("", .check(511, "目盛の間隔を自動で決める"))
        d.row("目盛の間隔", .field(515, w: 64))
        d.row("副目盛の分割数", .field(516, w: 36))
        d.group("目盛の付け方", id: 522) { g in
            g.row(nil, .radio(517, "等間隔", first: true))
            g.row(nil, .radio(518, "対数(指数で書く)", w: 84), .radio(520, "対数(値で書く)"))
            g.row(nil, .radio(519, "逆数(逆数で書く)", w: 84), .radio(521, "逆数(値で書く)"))
        }
        d.row(nil, .check(794, "目盛を式で変える"), .field(795, w: 96, disabled: true))
        d.checks([(512, "反対側の軸も同じにする"), (793, "ほかのグラフとつなぐ")])
    }

    static let axisTicks = DlgLayout.dialog(width: 210) { d in
        let rows: [(String, inside: Int, outside: Int, color: Int, width: Int, style: Int, pitch: Int, length: Int)] = [
            ("主目盛", 525, 527, 536, 529, 798, 533, 531),
            ("副目盛", 526, 528, 537, 530, 799, 534, 532),
        ]
        for r in rows {
            d.group(r.0) { g in
                g.labels("向き", "長さ", "線の種類", "線の太さ")
                g.row("向き", .check(r.inside, "内側"), .check(r.outside, "外側"))
                g.row("長さ", .field(r.length, w: 30), .text("mm"), .gap(6), .text("色"), .color(r.color))
                g.row("線の種類", .popup(r.style, w: 76))
                g.row("線の太さ", .field(r.width, w: 30), .text("mm"), .gap(4), .text("破線の間隔"), .field(r.pitch, w: 30), .text("mm"))
            }
        }
        d.group("軸の線") { g in
            g.labels("描く範囲", "交わる位置")
            g.row(nil, .check(551, "軸の線を一部だけ描く"))
            g.row("描く範囲", .field(541, w: 30), .text("〜"), .field(542, w: 30), .text("%"))
            g.row("交わる位置", .popup(544, w: 80))
        }
    }

    static let axisNumbers = DlgLayout.dialog(width: 210) { d in
        d.row(nil, .check(538, "目盛の数字を書く"))
        d.space(3)
        d.group("文字") { g in
            g.labels("書体", "大きさ", "スタイル")
            g.row("書体", .combo(742, w: 110))
            g.row("大きさ", .combo(789, w: 44), .text("pt"), .gap(6), .text("色"), .popup(790, w: 58, owner: true))
            g.row("スタイル", .popup(788, w: 72))
        }
        d.group("書き方") { g in
            g.checks([(547, "0.0 は 0 と書く"), (546, "0 を消さない"), (545, "正の数に + を付ける"), (548, "0 はほかの軸と共通")], columns: 2)
            g.checks([(549, "はみ出す桁も書く"), (550, "対数の 10⁰・10¹ は 1・10 と書く")])
        }
        d.group("位置と桁") { g in
            g.labels("ずらす", "書く目盛", "桁数")
            g.row("ずらす", .text("右"), .field(539, w: 28), .text("下"), .field(540, w: 28))
            g.row("書く目盛", .text("最初"), .field(541, w: 24), .text("個数"), .field(542, w: 24), .text("間隔"), .field(543, w: 24))
            g.row("桁数", .text("整数"), .popup(798, w: 36), .text("小数"), .popup(799, w: 36))
        }
    }

    // MARK: - グラフの設定(タブ 3 枚)

    static let graphFrame = DlgLayout.dialog(width: 200) { d in
        d.labels("左の余白", "線の太さ", "線の色")
        d.group("位置と大きさ(mm)") { g in
            g.row("左の余白", .field(501, w: 36), .gap(4), .text("上の余白：", w: 34, align: .right), .field(502, w: 36))
            g.row("幅", .field(503, w: 36), .gap(4), .text("高さ：", w: 34, align: .right), .field(504, w: 36))
        }
        d.group("線と背景") { g in
            g.row("線の太さ", .field(505, w: 30), .text("mm"))
            g.row("線の色", .color(523), .gap(4), .text("背景の色：", w: 34, align: .right), .color(708))
        }
        d.group("枠の形", id: 510) { g in
            g.radios([(507, "四角く囲む"), (506, "方眼"), (508, "左と下だけ"), (509, "軸だけ")], columns: 2)
        }
    }

    static let graphTitle = DlgLayout.dialog(width: 200) { d in
        d.labels("グラフの名前", "コメント", "表示の倍率")
        d.row("グラフの名前", .field(787, w: 120))
        d.row("コメント", .field(788, w: 120))
        d.row("表示の倍率", .field(789, w: 36), .text("%"))
        d.space(4)
        d.checks([(790, "%01N などの番号は、表示しているデータだけで数える")])
    }

    static let graphRanges = DlgLayout.dialog(width: 200) { d in
        DlgTemplate.rangeRows(&d)
    }

    /// X・Y・U・R の最小と最大(グラフの設定と範囲の指定で使う)
    private static func rangeRows(_ d: inout DlgLayout) {
        d.labelW = 36
        d.columnTitles([("最小", 60), ("最大", 60)])
        for (axis, check, lo, hi) in [("X 軸", 778, 787, 788), ("Y 軸", 779, 789, 790), ("U 軸", 780, 791, 792), ("R 軸", 781, 793, 794)] {
            d.row(nil, .check(check, axis, w: 36), .field(lo, w: 60), .field(hi, w: 60))
        }
    }

    // MARK: - 範囲・印刷・コピー

    static let trimming = DlgLayout.dialog("軸の範囲", width: 200) { d in
        DlgTemplate.rangeRows(&d)
        d.space(2)
        d.checks([(782, "最小と最大を小さい順に並べ替える")])
        d.buttons(right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let printSize = DlgLayout.dialog("印刷の大きさ", width: 200) { d in
        d.labels("用紙", "幅", "向き", "拡大・縮小")
        d.row("用紙", .popup(787, w: 100, owner: true))
        d.row("幅", .field(788, w: 36), .text("mm"), .gap(4), .text("長さ"), .field(789, w: 36), .text("mm"))
        d.row("向き", .radio(790, "縦", first: true), .radio(791, "横"))
        d.row("拡大・縮小", .combo(810, w: 50), .text("%"))
        d.buttons(right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let copyRegion = DlgLayout.dialog("コピーする範囲", width: 210) { d in
        d.labels("左", "縮小率", "解像度")
        d.columnTitles([("余白", 44), ("位置", 44)])
        for (name, margin, pos) in [("左", 787, 778), ("上", 788, 779), ("右", 789, 780), ("下", 790, 781)] {
            d.row(name, .field(margin, w: 44), .field(pos, w: 44, readOnly: true), .text("mm"))
        }
        d.space(3)
        d.row("縮小率", .field(791, w: 44), .text("%"))
        d.row("解像度", .field(792, w: 44, disabled: true), .text("dpi"))
        d.row("", .check(794, "EMF で書き出す"))
        d.buttons(left: [(920, "初めの値に戻す")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    // MARK: - データの設定(タブ 3 枚。曲線のあるときは lsqDraw を 4 枚目に付ける)

    static let dataFile = DlgLayout.dialog(width: 240) { d in
        d.note("", id: 731)
        d.row(nil, .check(793, "このデータを表示する"), .gap(8), .popup(911, w: 84))
        d.labels("横の値の列", "縦の値の列")
        d.row("横の値の列", .combo(601, w: 64), .gap(8), .radio(614, "誤差 (+, +)", manual: true), .radio(787, "誤差 (±)", manual: true))
        d.row("縦の値の列", .combo(602, w: 64), .gap(8), .radio(615, "誤差 (+, +)", manual: true), .radio(788, "誤差 (±)", manual: true))
        d.textArea(732, h: 56, readOnly: true)
        DlgTemplate.dataButtons(&d)
    }

    static let dataLook = DlgLayout.dialog(width: 240) { d in
        d.note("", id: 731)
        d.split(0.5, { l in
            l.group("点") { g in
                g.labels("形", "大きさ", "色", "中の色", "塗り")
                g.row("形", .popup(701, w: 60, owner: true))
                g.row("大きさ", .field(717, w: 30), .text("mm"))
                g.row("色", .color(709))
                g.row("中の色", .color(719))
                g.row("塗り", .popup(778, w: 60))
            }
        }, { r in
            r.group("線") { g in
                g.labels("種類", "太さ", "破線の間隔", "色")
                g.row("種類", .popup(702, w: 48, owner: true))
                g.row("太さ", .field(707, w: 30), .text("mm"))
                g.row("破線の間隔", .field(770, w: 30), .text("mm"))
                g.row("色", .color(708))
                let w = g.width
                g.sample(794, w: w, h: 16)
            }
        })
        d.group("値を式で変える") { g in
            g.row(nil, .check(703, "横の値", w: 44), .combo(704, w: 156))
            g.row(nil, .check(705, "縦の値", w: 44), .combo(706, w: 156))
        }
        DlgTemplate.dataButtons(&d)
    }

    static let dataRead = DlgLayout.dialog(width: 240) { d in
        d.note("", id: 731)
        d.group("読む行") { g in
            g.labels("初めに飛ばす行", "読む行数", "何行ごとに読むか")
            g.row("初めに飛ばす行", .field(611, w: 34))
            g.row("読む行数", .field(612, w: 34), .gap(4), .check(791, "ファイルの先頭から数える"))
            g.row("何行ごとに読むか", .field(787, w: 34))
            g.checks([(792, "コメントの行などは数えない"), (790, "タブを空白と同じに扱う")])
        }
        d.labels("隣を平均", "棒の根もとの値")
        d.row("隣を平均", .text("横"), .field(788, w: 28), .text("個"), .gap(6), .text("縦"), .field(789, w: 28), .text("個"))
        d.row("棒の根もとの値", .field(793, w: 50))
        d.split(0.5, { l in
            l.group("横の軸", id: 713) { g in g.radios([(711, "X 軸"), (712, "U 軸")], columns: 2) }
        }, { r in
            r.group("縦の軸", id: 716) { g in g.radios([(714, "Y 軸"), (715, "R 軸")], columns: 2) }
        })
        DlgTemplate.dataButtons(&d)
    }

    /// データの設定のページの下の押しボタン
    private static func dataButtons(_ d: inout DlgLayout) {
        d.row(nil, .push(557, "全体の既定にする"), .push(558, "拡張子の既定にする"), .push(559, "ファイルを選ぶ…"))
    }

    // MARK: - 最小二乗・曲線

    static let lsqOrder = DlgLayout.dialog(width: 240) { d in
        d.note("", id: 731)
        d.labels("次数", "x0", "y0")
        d.row("次数", .popup(671, w: 72))
        d.space(2)
        d.row(nil, .check(672, "決めた点を必ず通す"))
        d.row("x0", .field(673, w: 60))
        d.row("y0", .field(674, w: 60))
        d.space(6)
        d.row(nil, .push(557, "既定にする"))
    }

    static let generalFunction = DlgLayout.dialog(width: 240) { d in
        d.labels("f(x)")
        d.row("f(x)", .field(777, w: 176))
        let indent = d.labelW + DlgLayout.gap
        d.slider(820, indent: indent)
        d.space(3)
        d.labelW = 26
        d.columnTitles([("初めの値", 50), ("", 30), ("偏微分", 96)])
        for (k, name) in ["a", "b", "c", "d", "e", "f", "g", "h", "i"].enumerated() {
            d.row(nil, .check(811 + k, name, w: 26), .field(787 + k, w: 50),
                  .text("∂f/∂\(name)", w: 30, align: .right), .field(778 + k, w: 96))
        }
        d.space(3)
        d.labels("許容誤差")
        d.row("許容誤差", .field(796, w: 40), .text("%"))
        d.row(nil, .push(557, "既定にする"))
    }

    static let lsqDraw = DlgLayout.dialog(width: 240) { d in
        d.note("", id: 731)
        d.split(0.5, { l in
            l.group("描く範囲") { g in
                g.labels("始まり", "終わり", "分割数")
                g.row("始まり", .field(513, w: 50))
                g.row("終わり", .field(514, w: 50))
                g.row("分割数", .field(515, w: 50))
            }
        }, { r in
            r.group("線") { g in
                g.labels("種類", "太さ", "破線の間隔", "色")
                g.row("種類", .popup(677, w: 48))
                g.row("太さ", .field(675, w: 30), .text("mm"))
                g.row("破線の間隔", .field(770, w: 30), .text("mm"))
                g.row("色", .color(676))
            }
        })
        d.row(nil, .check(793, "グラフの範囲の外にある点も使う"))
        d.group("曲線の点の間隔", id: 522) { g in
            g.radios([(517, "等間隔"), (518, "指数的"), (519, "逆数的")], columns: 3)
        }
        d.row(nil, .push(557, "既定にする"))
    }

    static let lsqResult = DlgLayout.dialog("当てはめの結果", width: 210) { d in
        d.note("", id: 731, align: .center)
        d.list(732, h: 60)
        d.buttons(left: [(7, "コピー"), (797, "グラフに文字で貼る")], right: [(IDC.ok, "OK")])
    }

    static let fittingStart = DlgLayout.dialog("当てはめの条件", width: 230) { d in
        d.note("チェックした値を動かして当てはめます。")
        d.split(0.6, { l in
            l.labelW = 64
            l.columnTitles([("初めの値", 44)])
            for k in 0..<9 {
                let name = ["強さ", "位置", "半値幅"][k % 3]
                l.row(nil, .check(2001 + k, name, w: 64), .field(2011 + k, w: 44))
                if k % 3 == 2 { l.space(3) }
            }
            l.row(nil, .check(2010, "オフセット", w: 64), .field(2020, w: 44))
        }, { r in
            r.labels("ピークの数", "精度")
            r.row("ピークの数", .popup(2023, w: 36))
            r.row("精度", .field(2024, w: 36))
            r.space(6)
            r.row(nil, .push(2021, "1〜3 番", w: 56))
            r.row(nil, .push(2022, "4〜6 番", w: 56))
        })
        d.buttons(right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let constants = DlgLayout.dialog("定数", width: 220) { d in
        let names = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
        d.split(0.5, { l in
            for k in 0..<5 { l.row(nil, .text(names[k] + " =", w: 14, align: .right), .field(787 + k, w: 72)) }
        }, { r in
            for k in 5..<9 { r.row(nil, .text(names[k] + " =", w: 14, align: .right), .field(787 + k, w: 72)) }
        })
        d.row(nil, .push(917, "コピー"), .push(918, "ペースト"))
        d.buttons(right: [(919, "適用"), (IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    // MARK: - 文字・矢印・点・画像・枠

    static let textObject = DlgLayout.dialog("文字", width: 320) { d in
        d.textArea(741, h: 44)
        d.row(nil, .push(748, "文字の書き方…"), .gap(8), .text("記号を入れる"), .combo(744, w: 90))
        d.split(0.5, { l in
            l.group("文字の形") { g in
                g.labels("欧文", "和文", "大きさ", "スタイル", "色")
                g.row("欧文", .combo(742, w: 90))
                g.row("和文", .combo(743, w: 90))
                g.row("大きさ", .combo(789, w: 40), .text("pt"))
                g.row("スタイル", .popup(788, w: 64))
                g.row("色", .popup(790, w: 56, owner: true))
            }
        }, { r in
            r.group("置き方") { g in
                g.labels("位置", "向き")
                g.row("位置", .text("x"), .field(746, w: 34), .text("y"), .field(747, w: 34), .text("mm"))
                g.row("向き", .combo(745, w: 40), .text("度"))
                g.checks([(912, "位置を絶対値で決める"), (787, "背景を透かさない")])
            }
            r.group("揃え", id: 522) { g in
                g.radios([(908, "左"), (909, "中央"), (910, "右")], columns: 3)
            }
        })
        d.buttons(left: [(797, "マウスで置く"), (7, "削除")], right: [(557, "既定にする"), (IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let arrow = DlgLayout.dialog("矢印", width: 260) { d in
        d.split(0.5, { l in
            l.group("線") { g in
                g.labels("種類", "太さ", "破線の間隔", "色")
                g.row("種類", .popup(702, w: 56))
                g.row("太さ", .field(751, w: 30), .text("mm"))
                g.row("破線の間隔", .field(753, w: 30), .text("mm"))
                g.row("色", .color(758))
            }
        }, { r in
            r.group("矢じり") { g in
                g.labels("形", "長さ", "開き", "閉じ")
                g.row("形", .popup(800, w: 60, owner: true))
                g.row("長さ", .field(752, w: 30), .text("mm"))
                g.row("開き", .field(826, w: 30))
                g.row("閉じ", .field(827, w: 30))
            }
        })
        d.group("位置") { g in
            g.labels("始まり", "終わり")
            g.columnTitles([("X", 50), ("Y", 50)])
            g.row("始まり", .field(754, w: 50), .field(755, w: 50))
            g.row("終わり", .field(756, w: 50), .field(757, w: 50))
            g.split(0.5, { a in
                a.group("X の基準", id: 759) { b in b.radios([(760, "mm"), (761, "X 軸"), (762, "U 軸")], columns: 3) }
            }, { a in
                a.group("Y の基準", id: 763) { b in b.radios([(764, "mm"), (765, "Y 軸"), (766, "R 軸")], columns: 3) }
            })
        }
        d.row(nil, .push(797, "マウスで置く"), .push(718, "既定にする"))
        d.buttons(left: [(7, "削除")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let dot = DlgLayout.dialog("点", width: 250) { d in
        d.split(0.5, { l in
            l.group("点") { g in
                g.labels("形", "大きさ", "色", "中の色", "塗り")
                g.row("形", .popup(701, w: 60, owner: true))
                g.row("大きさ", .field(717, w: 30), .text("mm"))
                g.row("色", .color(709))
                g.row("中の色", .color(719))
                g.row("塗り", .popup(778, w: 60))
            }
        }, { r in
            r.group("線") { g in
                g.labels("種類", "太さ", "破線の間隔", "色")
                g.row("種類", .popup(702, w: 50))
                g.row("太さ", .field(707, w: 30), .text("mm"))
                g.row("破線の間隔", .field(770, w: 30), .text("mm"))
                g.row("色", .color(708))
                let lw = g.labelW
                g.row(nil, .text("線の長さ：", w: lw, id: 793, align: .right), .field(749, w: 30))
            }
        })
        d.labels("位置")
        d.row("位置", .text("x"), .field(746, w: 40), .text("y"), .field(747, w: 40))
        d.row(nil, .push(797, "マウスで置く"))
        d.buttons(left: [(7, "削除")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let picture = DlgLayout.dialog("画像", width: 240) { d in
        d.labels("ファイル", "位置", "幅", "高さ")
        d.row("ファイル", .field(741, w: 120), .push(746, "選ぶ…", w: 44))
        d.row("位置", .text("x"), .field(754, w: 40), .text("y"), .field(755, w: 40))
        d.row("幅", .field(787, w: 40), .text("mm"), .gap(6), .text("", w: 60, id: 778))
        d.row("高さ", .field(788, w: 40, readOnly: true), .text("mm"), .gap(6), .text("", w: 60, id: 779))
        d.row("", .check(912, "位置を絶対値で決める"))
        d.buttons(left: [(7, "削除")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let box = DlgLayout.dialog("枠", width: 230) { d in
        d.group("位置") { g in
            g.labels("始まり", "終わり")
            g.columnTitles([("X", 50), ("Y", 50)])
            g.row("始まり", .field(754, w: 50), .field(755, w: 50))
            g.row("終わり", .field(756, w: 50), .field(757, w: 50))
            g.row("", .check(912, "位置を絶対値で決める"))
        }
        d.group("線と影") { g in
            g.labels("線の太さ", "影の長さ", "色", "角の丸み")
            g.row("線の太さ", .field(751, w: 30), .text("mm"))
            g.row("影の長さ", .field(752, w: 30), .text("mm"))
            g.row("色", .text("線と影"), .color(708), .gap(6), .text("中"), .color(758))
            g.row("角の丸み", .text("大きさ"), .field(787, w: 30), .text("縦横比"), .field(788, w: 30))
        }
        d.row(nil, .push(797, "マウスで置く"), .push(718, "既定にする"))
        d.buttons(left: [(7, "削除")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    // MARK: - 設定(タブ 2 枚)

    static let settingsFiles = DlgLayout.dialog(width: 300) { d in
        d.group("SMP ファイル") { g in
            g.checks([(787, "SMP にデータも入れる"),
                      (794, "データと SMP が同じフォルダなら、データの場所を書かない"),
                      (900, "一時ファイルを優先する"),
                      (899, "SMP はできるだけテキストで書く")])
        }
        d.group("データ") { g in
            g.labels("ファイルの種類", "使うエディタ")
            g.row("ファイルの種類", .field(902, w: 90))
            g.row("使うエディタ", .field(781, w: 150), .push(782, "選ぶ…", w: 44))
            g.checks([(795, "起動時に開くファイルでもプロパティを設定する")])
            g.space(2)
            g.note("新しいデータを開いたとき")
            g.checks([(821, "点の形を変える"), (822, "線の種類を変える"), (823, "点の色を変える"),
                      (824, "線の色を変える"), (828, "X の範囲を合わせる"), (829, "Y の範囲を合わせる")], columns: 2, indent: 8)
        }
    }

    static let settingsView = DlgLayout.dialog(width: 300) { d in
        d.group("表示") { g in
            g.checks([(788, "ツールバーを表示"), (789, "ステータスバーを表示"),
                      (790, "グラフの枠の外を描かない"), (903, "背景の色を印刷にも使う")], columns: 2)
            g.space(2)
            g.labels("表示の大きさ", "スナップ", "グリッド", "背景の色")
            g.row("表示の大きさ", .combo(793, w: 44), .text("%"))
            g.row("スナップ", .popup(791, w: 76))
            g.row("グリッド", .popup(792, w: 76), .gap(6), .text("色"), .color(710))
            g.row("背景の色", .color(708), .gap(6), .text("値を読む印の色"), .color(709))
        }
        d.group("並べ替え") { g in
            g.checks([(825, "読んだ値を並べ替える"), (914, "トリミングの値を並べ替える")], columns: 2)
        }
        d.group("上付き・下付きの文字") { g in
            g.labels("大きさ", "位置")
            g.row("大きさ", .field(778, w: 30), .text("%"))
            g.row("位置", .text("上付き"), .field(779, w: 30), .text("%"), .gap(6), .text("下付き"), .field(780, w: 30), .text("%"))
        }
        d.checks([(916, "印刷するときフッターを付ける")])
    }

    // MARK: - 一覧・入力・そのほか

    static let chooseMany = DlgLayout.dialog("ファイルを選ぶ", width: 240) { d in
        d.list(561, h: 90, multi: true, owner: true)
        d.buttons(left: [(768, "すべて選ぶ"), (767, "新しく…")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "選ぶ")])
    }

    static let maskTarget = DlgLayout.dialog("マスクをかけるデータ", width: 240) { d in
        d.list(561, h: 90, owner: true)
        d.buttons(left: [(767, "All")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "選ぶ")])
    }

    static let chooseOne = DlgLayout.dialog("ファイルを選ぶ", width: 240) { d in
        d.list(561, h: 90, owner: true)
        d.buttons(left: [(767, "新しく…")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "選ぶ")])
    }

    static let dataManager = DlgLayout.dialog("データの管理", width: 240) { d in
        d.list(561, h: 96, multi: true, owner: true)
        d.row(nil, .push(787, "上へ", w: 40), .push(788, "下へ", w: 40), .gap(8), .push(768, "すべて選ぶ"))
        d.buttons(left: [(789, "データを閉じる")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let maskChoice = DlgLayout.dialog("データマスク", width: 280) { d in
        d.note("対象: Xmin Xmax, Ymin Ymax(All はすべてのデータ)")
        d.list(561, h: 70)
        d.buttons(left: [(767, "新しく…")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "削除")])
    }

    static let input = DlgLayout.dialog(width: 220) { d in
        d.note("", id: 901)
        let w = d.width
        d.row(nil, .field(902, w: w))
        d.buttons(right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let missingFiles = DlgLayout.dialog("確認", width: 240) { d in
        d.note("次のファイルが開けませんでした。")
        d.list(561, h: 80, owner: true)
        d.buttons(left: [(559, "探す…")], right: [(IDC.cancel, "キャンセル"), (IDC.ok, "OK")])
    }

    static let readValue = DlgLayout.dialog("値を読む", width: 150) { d in
        d.labelW = 30
        d.row("番号", .text("", w: 90, id: 789))
        d.row(nil, .text("X：", w: 30, id: 904, align: .right), .field(787, w: 90, readOnly: true))
        d.row(nil, .text("Y：", w: 30, id: 905, align: .right), .field(788, w: 90, readOnly: true))
        d.row(nil, .push(784, "|◀", w: 18), .push(778, "◀◀", w: 18), .push(779, "◀", w: 18),
              .push(780, "▶", w: 18), .push(781, "▶▶", w: 18), .push(785, "▶|", w: 18))
        d.slider(820)
        d.row(nil, .push(782, "印を付ける", w: 61), .push(783, "平均する", w: 61))
        d.row("平均 x", .text("", w: 90, id: 906))
        d.row("平均 y", .text("", w: 90, id: 907))
        d.buttons(right: [(IDC.ok, "閉じる")])
    }

    static let about = DlgLayout.dialog("Sma4 for Mac について", width: 210) { d in
        d.icon()
        d.note("Sma4 for Mac", align: .center)
        d.note("", id: 103, align: .center)
        d.space(4)
        d.note("SMP ファイルを開いて、編集して、", align: .center)
        d.note("保存できるグラフ作成アプリです。", align: .center)
        d.buttons(right: [(IDC.ok, "OK")])
    }

    /// 保存の画面に付ける選択肢
    static let saveOptions = DlgLayout.dialog(width: 300) { d in
        d.row(nil, .check(787, "SMP にデータも入れる"), .gap(8), .check(788, "16 ビット版の形式で保存する"))
    }

    /// 書き出しの画面に付ける選択肢
    static let separatorChoice = DlgLayout.dialog(width: 300) { d in
        d.row(nil, .radio(787, "タブで区切る", first: true), .gap(8), .radio(788, "カンマで区切る"))
    }
}
