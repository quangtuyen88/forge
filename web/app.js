// Landing v3: reveal-on-scroll, video pause off-screen, reduced-motion play buttons.
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
    // Safety net: nothing stays hidden if the observer never fires (in-app browsers, prerender).
    setTimeout(function () { revealEls.forEach(function (el) { el.classList.add("is-in"); }); }, 1500);
  } else {
    revealEls.forEach(function (el) { el.classList.add("is-in"); });
  }

  // Videos: play only while on screen. Under reduced motion they never autoplay —
  // the poster stays and a play button (CSS: .reduce-play .video-play) starts them.
  document.querySelectorAll("video").forEach(function (video) {
    if (reduced.matches) {
      video.removeAttribute("autoplay");
      document.documentElement.classList.add("reduce-play");
      var btn = video.parentElement.querySelector(".video-play");
      if (btn) {
        btn.addEventListener("click", function () {
          if (video.paused) {
            video.play().then(function () { btn.style.display = "none"; }).catch(function () {});
          } else {
            video.pause();
            btn.style.display = "";
          }
        });
        video.addEventListener("play", function () { btn.style.display = "none"; });
        video.addEventListener("pause", function () { btn.style.display = ""; });
      }
      return;
    }
    if (!("IntersectionObserver" in window)) return;
    var vio = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { video.play().catch(function () {}); }
        else { video.pause(); }
      });
    }, { threshold: 0.25 });
    vio.observe(video);
  });
})();
