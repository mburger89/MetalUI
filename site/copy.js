// Progressive enhancement: a copy button on each command block, only where the clipboard API exists.
if (navigator.clipboard) {
  document.querySelectorAll('pre[data-copy]').forEach(function (pre) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy';
    button.textContent = 'Copy';
    button.setAttribute('aria-label', 'Copy these commands');
    button.addEventListener('click', function () {
      var code = pre.querySelector('code');
      navigator.clipboard.writeText(code.innerText.replace(/\n$/, '')).then(function () {
        button.textContent = 'Copied';
        setTimeout(function () { button.textContent = 'Copy'; }, 1600);
      }, function () {
        button.textContent = 'Press Cmd/Ctrl+C';
      });
    });
    pre.parentNode.classList.add('has-copy');
    pre.parentNode.appendChild(button);
  });
}
