// ボタン操作とディスプレイ更新（カウントロジックは counter.js）。
(function () {
  var Counter = window.Counter;

  var count = Counter.MIN;

  var digitEls = document.querySelectorAll(".digit");
  var srText = document.querySelector(".sr-only");

  function render() {
    var chars = Counter.digits(count);
    digitEls.forEach(function (el, i) {
      if (chars[i] === " ") {
        el.removeAttribute("data-value");
      } else {
        el.setAttribute("data-value", chars[i]);
      }
    });
    if (srText) srText.textContent = "現在のカウント: " + count;
  }

  function bind(selector, fn) {
    var btn = document.querySelector(selector);
    if (!btn) return;
    btn.addEventListener("click", function () {
      count = fn(count);
      render();
    });
  }

  bind(".btn--plus", Counter.increment);
  bind(".btn--minus", Counter.decrement);
  bind(".btn--reset", Counter.reset);

  render();
})();
