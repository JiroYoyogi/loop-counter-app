// カウント値の保存・復元。
// パース/シリアライズは DOM・localStorage 非依存の純粋関数（テスト対象）。
(function (root) {
  var KEY = "loop-counter:count";
  var Counter = root.Counter || (typeof require !== "undefined" ? require("./counter") : null);

  // localStorage から読んだ生文字列を、有効なカウント値（0〜999）に変換する。
  // null / 数値でない / 範囲外 などはすべて 0 にフォールバック。
  function parseStored(raw) {
    if (raw === null || raw === undefined) return Counter.MIN;
    var n = Number(raw);
    if (!Number.isFinite(n)) return Counter.MIN;
    return Counter.clamp(n);
  }

  function serialize(count) {
    return String(Counter.clamp(count));
  }

  // 以下は localStorage への薄いラッパー。使えない環境でも例外で止まらない。
  function load(storage) {
    storage = storage || root.localStorage;
    try {
      return parseStored(storage.getItem(KEY));
    } catch (e) {
      return Counter.MIN;
    }
  }

  function save(count, storage) {
    storage = storage || root.localStorage;
    try {
      storage.setItem(KEY, serialize(count));
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
