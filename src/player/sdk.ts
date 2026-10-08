// The script injected at the top of every AI-made game. It runs inside the
// sandboxed iframe (opaque origin: no access to the app's storage or keys)
// and bridges the host's touch controls, errors and multiplayer messages.
//
// Kept as plain ES5-ish JavaScript in a string so it can be inlined anywhere.

export const SDK_SOURCE = String.raw`(function () {
  if (window.Combiner) return;
  var host = window.parent;
  var post = function (m) { m.__cmb = 1; try { host.postMessage(m, '*'); } catch (e) {} };
  var KEYS = {
    left: ['ArrowLeft', 'ArrowLeft', 37], right: ['ArrowRight', 'ArrowRight', 39],
    up: ['ArrowUp', 'ArrowUp', 38], down: ['ArrowDown', 'ArrowDown', 40],
    a: [' ', 'Space', 32], b: ['x', 'KeyX', 88], c: ['c', 'KeyC', 67]
  };
  var input = { x: 0, y: 0, left: false, right: false, up: false, down: false, a: false, b: false, c: false };
  var inputHandlers = [];

  function fire(type, k) {
    var d = KEYS[k], ev;
    try { ev = new KeyboardEvent(type, { key: d[0], code: d[1], bubbles: true, cancelable: true }); } catch (e) { return; }
    try {
      Object.defineProperty(ev, 'keyCode', { get: function () { return d[2]; } });
      Object.defineProperty(ev, 'which', { get: function () { return d[2]; } });
    } catch (e) {}
    var a = document.activeElement;
    var t = a && a !== document.body && a !== document.documentElement ? a : (document.body || document.documentElement);
    t.dispatchEvent(ev);
  }

  function setInput(s) {
    var n = {
      x: +s.x || 0, y: +s.y || 0,
      left: s.x < -0.4, right: s.x > 0.4, up: s.y < -0.4, down: s.y > 0.4,
      a: !!s.a, b: !!s.b, c: !!s.c
    };
    for (var k in KEYS) {
      if (n[k] && !input[k]) fire('keydown', k);
      else if (!n[k] && input[k]) fire('keyup', k);
    }
    for (var key in n) input[key] = n[key];
    for (var i = 0; i < inputHandlers.length; i++) { try { inputHandlers[i](input); } catch (e) { report(e); } }
  }

  var msgHandlers = [], playerHandlers = [];
  var net = {
    me: null, isHost: true, players: [], connected: false,
    send: function (data) { post({ type: 'net-send', data: data }); },
    onMessage: function (fn) { msgHandlers.push(fn); },
    onPlayers: function (fn) { playerHandlers.push(fn); if (net.connected) fn(net.players); }
  };

  window.Combiner = {
    version: 1,
    input: input,
    net: net,
    onInput: function (fn) { inputHandlers.push(fn); },
    /** Optional: tell the host your score so it can show it in the HUD. */
    setScore: function (score) { post({ type: 'score', score: +score || 0 }); },
    /** Optional: tell the host the game was won or lost. */
    gameOver: function (won, score) { post({ type: 'over', won: !!won, score: +score || 0 }); }
  };

  function report(err, line) {
    var msg = err && err.message ? err.message : String(err);
    post({ type: 'error', message: String(msg).slice(0, 400), line: line || 0 });
  }
  window.addEventListener('error', function (e) { report(e.error || e.message || 'Script error', e.lineno); });
  window.addEventListener('unhandledrejection', function (e) { report('Unhandled promise rejection: ' + (e.reason && e.reason.message || e.reason)); });

  window.addEventListener('message', function (e) {
    if (e.source !== host) return;
    var m = e.data;
    if (!m || m.__cmb !== 1) return;
    if (m.type === 'input') setInput(m.state);
    else if (m.type === 'net') {
      for (var i = 0; i < msgHandlers.length; i++) { try { msgHandlers[i](m.data, m.from); } catch (err) { report(err); } }
    } else if (m.type === 'players') {
      net.players = m.players; net.me = m.me; net.isHost = m.isHost; net.connected = true;
      for (var j = 0; j < playerHandlers.length; j++) { try { playerHandlers[j](m.players); } catch (err) { report(err); } }
    }
  });

  // Sandboxed frames cannot use real storage; give games a memory shim so
  // "save high score" code does not crash them.
  try { window.localStorage.getItem('x'); } catch (e) {
    var mk = function () {
      var mem = {};
      return {
        getItem: function (k) { return Object.prototype.hasOwnProperty.call(mem, k) ? mem[k] : null; },
        setItem: function (k, v) { mem[k] = String(v); },
        removeItem: function (k) { delete mem[k]; },
        clear: function () { mem = {}; },
        key: function (i) { return Object.keys(mem)[i] || null; },
        get length() { return Object.keys(mem).length; }
      };
    };
    try { Object.defineProperty(window, 'localStorage', { value: mk(), configurable: true }); } catch (e2) {}
    try { Object.defineProperty(window, 'sessionStorage', { value: mk(), configurable: true }); } catch (e3) {}
  }

  // Resume any WebAudio contexts on the first real tap inside the game.
  var ctxs = [];
  var AC = window.AudioContext || window.webkitAudioContext;
  if (AC) {
    var Wrapped = function () { var c = new (Function.prototype.bind.apply(AC, [null].concat([].slice.call(arguments))))(); ctxs.push(c); return c; };
    Wrapped.prototype = AC.prototype;
    window.AudioContext = Wrapped;
    if (window.webkitAudioContext) window.webkitAudioContext = Wrapped;
  }
  var wake = function () { for (var i = 0; i < ctxs.length; i++) { try { if (ctxs[i].state === 'suspended') ctxs[i].resume(); } catch (e) {} } };
  ['pointerdown', 'touchstart', 'keydown', 'mousedown'].forEach(function (t) { window.addEventListener(t, wake, true); });

  // Games own every touch: no page scrolling, zooming or text selection.
  var style = document.createElement('style');
  style.textContent = 'html,body{margin:0;overscroll-behavior:none;touch-action:none;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}';
  (document.head || document.documentElement).appendChild(style);

  post({ type: 'ready' });
})();`;
