import Foundation

/// All the words one language contributes to voice parsing, in a single table.
/// Adding a third language is a new table, not new parser code.
struct VoicePhraseTable: Sendable {
  let completeSet: [String]
  let nextExercise: [String]
  let skipRest: [String]
  let startRest: [String]          // bare "start rest"
  let restMinuteWords: [String]    // minute, minutes, phút
  let restSecondWords: [String]    // second, seconds, giây
  let addWords: [String]           // add, plus, thêm
  let removeWords: [String]        // minus, remove, drop, bớt, giảm
  let kiloWords: [String]          // kg, kilo, kilos, ký, cân
  let poundWords: [String]
  let repWords: [String]           // rep, reps, cái, lần
  let makeItWords: [String]        // make it, đổi thành, để
  let confirm: [String]
  let cancel: [String]
  let undo: [String]
  let askCoach: [String]           // ask coach, hỏi coach, hỏi huấn luyện viên
  let swapVerbs: [String]          // swap, change, replace, đổi, thay
  let activation: [String]         // coach, hey coach, regulift, huấn luyện viên
  let connectors: [String]         // at, for, by, to, and — words that mean the sentence is unfinished
  let numbers: [String: Int]       // word numbers for that language

  static func forLanguage(_ language: VoiceLanguage) -> VoicePhraseTable {
    language == .en ? .english : .vietnamese
  }

  static let english = VoicePhraseTable(
    completeSet: ["complete set", "done", "log it", "thats it"],
    nextExercise: ["next exercise", "move on"],
    skipRest: ["skip rest", "skip the timer"],
    startRest: ["start rest"],
    restMinuteWords: ["minute", "minutes", "min", "mins"],
    restSecondWords: ["second", "seconds", "sec", "secs"],
    addWords: ["add", "plus"],
    removeWords: ["minus", "take off", "remove", "drop"],
    kiloWords: ["kg", "kilo", "kilos", "kilograms"],
    poundWords: ["lb", "lbs", "pounds"],
    repWords: ["rep", "reps"],
    makeItWords: ["make it"],
    confirm: ["confirm", "yes", "do it", "go ahead"],
    cancel: ["cancel", "no", "stop", "never mind"],
    undo: ["undo", "undo that", "scratch that"],
    askCoach: ["ask coach", "coach"],
    swapVerbs: ["swap", "change", "replace"],
    activation: ["coach", "hey coach", "regulift"],
    connectors: ["at", "for", "by", "to", "and", "plus", "minus"],
    numbers: [
      "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
      "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
      "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
      "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
  )

  // Vietnamese number keys are stored folded because folding merges "một"/"mốt"
  // and "mười"/"mươi" into one key each; the parser tells "mười" (10) from
  // "mươi" (×10) by position. "không" (zero) is deliberately absent — as a bare
  // command it means "cancel", and zero is never spoken as a weight or rep count.
  static let vietnamese = VoicePhraseTable(
    completeSet: ["xong", "xong rồi", "ghi lại", "hoàn thành"],
    nextExercise: ["bài tiếp", "bài tiếp theo", "tiếp theo"],
    skipRest: ["bỏ nghỉ", "bỏ qua nghỉ", "hết nghỉ"],
    startRest: ["nghỉ", "bắt đầu nghỉ"],
    restMinuteWords: ["phút"],
    restSecondWords: ["giây"],
    addWords: ["thêm"],
    removeWords: ["bớt", "giảm"],
    kiloWords: ["ký", "kí", "cân", "kg"],
    poundWords: [],
    repWords: ["lần", "cái"],
    makeItWords: ["đổi thành", "để"],
    confirm: ["xác nhận", "đồng ý", "được"],
    cancel: ["hủy", "không", "thôi"],
    undo: ["hoàn tác", "bỏ"],
    askCoach: ["hỏi coach", "hỏi huấn luyện viên"],
    swapVerbs: ["đổi", "thay"],
    activation: ["huấn luyện viên"],
    connectors: [],
    numbers: [
      "mot": 1, "hai": 2, "ba": 3, "bon": 4, "tu": 4, "nam": 5, "lam": 5,
      "sau": 6, "bay": 7, "tam": 8, "chin": 9, "muoi": 10, "tram": 100,
    ]
  )
}
