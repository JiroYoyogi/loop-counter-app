// ボタン操作とディスプレイ更新（カウントロジックは counter.js、保存は storage.js）。
(function () {
  var Counter = window.Counter;
  var Storage = window.CounterStorage;

  var count = Storage.load();

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

  var saveBtn = document.querySelector(".btn--save");
  if (saveBtn) {
    saveBtn.addEventListener("click", function () {
      Storage.save(count);
    });
  }

  render();
})();
