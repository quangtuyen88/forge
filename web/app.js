// Landing v2: reveal-on-scroll and the screens-strip prev/next buttons.
(function () {
  document.documentElement.classList.add("js");

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)");

  // Reveal sections/cards once as they enter the viewport.
  var revealEls = document.querySelectorAll("[data-reveal]");
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -10% 0px" });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add("is-in"); });
  }

  // Screens strip: keyboard-operable prev/next buttons, no auto-rotation.
  var strip = document.querySelector(".strip");
  document.querySelectorAll("[data-strip-prev], [data-strip-next]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      if (!strip) return;
      var dir = btn.hasAttribute("data-strip-next") ? 1 : -1;
      strip.scrollBy({ left: dir * strip.clientWidth * 0.8, behavior: reduced.matches ? "auto" : "smooth" });
    });
  });
})();
