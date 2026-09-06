// カウントロジック（DOM に依存しない純粋関数）。
// ブラウザでは window.Counter、Jest では module.exports で参照する。
(function (root) {
  var MIN = 0;
  var MAX = 999;

  function clamp(n) {
    if (typeof n !== "number" || Number.isNaN(n)) return MIN;
    return Math.min(MAX, Math.max(MIN, Math.trunc(n)));
  }

  function increment(n) {
    return clamp(clamp(n) + 1);
  }

  function decrement(n) {
    return clamp(clamp(n) - 1);
  }

  function reset() {
    return MIN;
  }

  // 3桁ぶんの表示文字を返す。余分な先頭桁は " "（消灯）。
  // 例: 5 -> [" ", " ", "5"] / 42 -> [" ", "4", "2"] / 999 -> ["9", "9", "9"]
  function digits(n) {
    return String(clamp(n)).padStart(3, " ").split("");
  }

  root.Counter = { MIN: MIN, MAX: MAX, clamp: clamp, increment: increment, decrement: decrement, reset: reset, digits: digits };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = root.Counter;
  }
})(typeof window !== "undefined" ? window : globalThis);
