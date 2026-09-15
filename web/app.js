// Waitlist form → POST /waitlist, keep ?ref= from the landing URL, show share code.
(function () {
  var form = document.getElementById("waitlist");
  var result = document.getElementById("result");
  var errorBox = document.getElementById("error");
  var shareLink = document.getElementById("share-link");
  var copyBtn = document.getElementById("copy");
  if (!form) return;

  var ref = new URLSearchParams(window.location.search).get("ref") || "";

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    errorBox.hidden = true;
    var email = document.getElementById("email").value.trim();
    if (!email) return;

    fetch(form.action, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: email, ref: ref }),
    })
      .then(function (res) {
        return res.json().then(function (data) { return { ok: res.ok, data: data }; });
      })
      .then(function (out) {
        if (!out.ok || !out.data.code) throw new Error(out.data.error || "Something went wrong. Try again.");
        var link = "https://forge-coach.quangtuyen88.workers.dev/r/" + out.data.code;
        shareLink.textContent = link;
        result.hidden = false;
        form.hidden = true;
      })
      .catch(function (err) {
        errorBox.textContent = err.message || "Something went wrong. Try again.";
        errorBox.hidden = false;
      });
  });

  copyBtn.addEventListener("click", function () {
    var link = shareLink.textContent;
    function done() {
      copyBtn.textContent = "Copied";
      setTimeout(function () { copyBtn.textContent = "Copy"; }, 1600);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(link).then(done, done);
    } else {
      var input = document.createElement("input");
      input.value = link;
      document.body.appendChild(input);
      input.select();
      document.execCommand("copy");
      document.body.removeChild(input);
      done();
    }
  });

  document.getElementById("year").textContent = String(new Date().getFullYear());
})();
