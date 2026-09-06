(() => {
  const phrases = [...document.querySelectorAll(".notification-message > span")];
  const toggle = document.querySelector(".notification-toggle");
  if (phrases.length < 2 || !toggle) return;

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  let current = 0;
  let paused = false;
  let timer;

  function updateRotation() {
    window.clearInterval(timer);
    toggle.hidden = reducedMotion.matches;
    if (paused || reducedMotion.matches || document.hidden) return;

    timer = window.setInterval(() => {
      phrases[current].classList.remove("is-visible");
      current = (current + 1) % phrases.length;
      phrases[current].classList.add("is-visible");
    }, 6000);
  }

  toggle.addEventListener("click", () => {
    paused = !paused;
    toggle.setAttribute("aria-label", paused ? "Resume rotating phrases" : "Pause rotating phrases");
    toggle.querySelector("path").setAttribute("d", paused ? "M4 2l5 4-5 4Z" : "M4 2v8M8 2v8");
    updateRotation();
  });

  reducedMotion.addEventListener("change", updateRotation);
  document.addEventListener("visibilitychange", updateRotation);
  updateRotation();
})();
