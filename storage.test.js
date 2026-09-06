const { KEY, parseStored, serialize, load, save } = require("./storage");

// テスト用の簡易 Storage 実装
function makeStorage(initial) {
  let store = { ...(initial || {}) };
  return {
    getItem: (k) => (k in store ? store[k] : null),
    setItem: (k, v) => {
      store[k] = String(v);
    },
    _dump: () => store,
  };
}

describe("parseStored", () => {
  test("有効な数値文字列はその値", () => {
    expect(parseStored("0")).toBe(0);
    expect(parseStored("42")).toBe(42);
    expect(parseStored("999")).toBe(999);
  });
  test("null / 不正値は 0", () => {
    expect(parseStored(null)).toBe(0);
    expect(parseStored("abc")).toBe(0);
    expect(parseStored("")).toBe(0);
  });
  test("範囲外はクランプ", () => {
    expect(parseStored("1500")).toBe(999);
    expect(parseStored("-5")).toBe(0);
  });
});

describe("serialize", () => {
  test("クランプした文字列を返す", () => {
    expect(serialize(42)).toBe("42");
    expect(serialize(1500)).toBe("999");
    expect(serialize(-1)).toBe("0");
  });
});

describe("load / save", () => {
  test("保存した値を読み戻せる", () => {
    const s = makeStorage();
    save(123, s);
    expect(s._dump()[KEY]).toBe("123");
    expect(load(s)).toBe(123);
  });
  test("未保存なら 0", () => {
    expect(load(makeStorage())).toBe(0);
  });
  test("getItem が例外を投げても 0 を返す", () => {
    const throwing = {
      getItem: () => {
        throw new Error("blocked");
      },
    };
    expect(load(throwing)).toBe(0);
  });
  test("setItem が例外を投げても false を返し停止しない", () => {
    const throwing = {
      setItem: () => {
        throw new Error("quota");
      },
    };
    expect(save(1, throwing)).toBe(false);
  });
});
