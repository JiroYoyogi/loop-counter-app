// カウント値の保存・復元。
// パース/シリアライズは DOM・localStorage 非依存の純粋関数（テスト対象）。
(function (root) {
  var KEY = "loop-counter:count";
  var Counter = root.Counter || (typeof require !== "undefined" ? require("./counter") : null);

  // localStorage から読んだ生文字列を、有効なカウント値（0〜999 の整数）に変換する。
  // null / 数値でない / 整数でない / 範囲外 などはすべて 0 にフォールバック。
  function parseStored(raw) {
    if (raw === null || raw === undefined) return Counter.MIN;
    var n = Number(raw);
    if (!Number.isInteger(n)) return Counter.MIN;
    if (n < Counter.MIN || n > Counter.MAX) return Counter.MIN;
    return n;
  }

  function serialize(count) {
    return String(Counter.clamp(count));
  }

  // 以下は localStorage への薄いラッパー。
  // localStorage の参照自体が例外を投げる環境（無効化・SecurityError 等）でも
  // 停止しないよう、参照取得も含めて try 内で処理する。
  function load(storage) {
    try {
      var s = storage || root.localStorage;
      return parseStored(s.getItem(KEY));
    } catch (e) {
      return Counter.MIN;
    }
  }

  function save(count, storage) {
    try {
      var s = storage || root.localStorage;
      s.setItem(KEY, serialize(count));
      return true;
    } catch (e) {
      return false;
    }
  }

  root.CounterStorage = { KEY: KEY, parseStored: parseStored, serialize: serialize, load: load, save: save };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = root.CounterStorage;
  }
})(typeof window !== "undefined" ? window : globalThis);
