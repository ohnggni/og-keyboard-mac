/// 자판 하나: 0x21~0x7E 각 ASCII 키에 대응하는 값(자모 또는 기호) 표.
struct Layout {
    let id: String
    let name: String
    /// 두벌식 계열: 자음이 초성/받침 구분 없이 들어오고 엔진이 위치를 정한다
    let dubeol: Bool
    private let table: [Int]

    init(id: String, name: String, dubeol: Bool, table: [Int]) {
        precondition(table.count == 0x7e - 0x21 + 1, "자판 표 크기 오류: \(id)")
        self.id = id
        self.name = name
        self.dubeol = dubeol
        self.table = table
    }

    /// ASCII 문자를 이 자판의 값으로 바꾼다. 범위 밖이면 그대로 돌려준다.
    func map(_ ascii: Int) -> Int {
        guard ascii >= 0x21 && ascii <= 0x7e else { return ascii }
        return table[ascii - 0x21]
    }
}
