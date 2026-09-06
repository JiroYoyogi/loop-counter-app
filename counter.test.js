const { MIN, MAX, increment, decrement, reset, digits } = require("./counter");

describe("increment", () => {
  test("1増える", () => {
    expect(increment(0)).toBe(1);
    expect(increment(41)).toBe(42);
  });
  test("999で頭打ち", () => {
    expect(increment(999)).toBe(MAX);
  });
});

describe("decrement", () => {
  test("1減る", () => {
    expect(decrement(42)).toBe(41);
  });
  test("0で頭打ち（負数にならない）", () => {
    expect(decrement(0)).toBe(MIN);
    expect(decrement(-5)).toBe(0);
  });
});

describe("reset", () => {
  test("0になる", () => {
    expect(reset(123)).toBe(0);
  });
});

describe("digits", () => {
  test("先頭の余分な桁は空白", () => {
    expect(digits(0)).toEqual([" ", " ", "0"]);
    expect(digits(5)).toEqual([" ", " ", "5"]);
    expect(digits(42)).toEqual([" ", "4", "2"]);
    expect(digits(999)).toEqual(["9", "9", "9"]);
  });
  test("範囲外はクランプされる", () => {
    expect(digits(1500)).toEqual(["9", "9", "9"]);
    expect(digits(-1)).toEqual([" ", " ", "0"]);
  });
});
