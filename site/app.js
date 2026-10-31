// Treatly site: a small replay of the app's pet loop, drawn from the real pet packs.
(() => {
  const PETS = ['shiba', 'golden', 'husky', 'chihuahua', 'corgi', 'orange-tabby', 'black-cat', 'siamese', 'calico', 'tuxedo', 'sheep', 'panda', 'capybara', 'mighty'];
  const PERSONALITY = {
    shiba: 'Sassy, dramatic screamer',
    golden: 'Patient and hopeful',
    husky: 'Loud, energetic, howls about everything',
    chihuahua: 'Tiny, yappy, runs everywhere',
    corgi: 'Bossy herder on tiny legs',
    'orange-tabby': 'Chaotic, random zoomies',
    'black-cat': 'Sleepy, silent and mysterious',
    siamese: 'Very talkative, the loudest of the cats',
    calico: 'Moody, changes her mind a lot',
    tuxedo: 'Polite but insistent, like a tiny butler',
    sheep: 'Slow, sleepy, bleats politely',
    panda: 'Lazy, dozes off mid-nag',
    capybara: 'Extremely chill, nags very politely',
    mighty: 'Huge, grumpy, pounds its chest',
  };
  const WEAR = [['none', 'None'], ['party-hat', 'Party hat'], ['bow', 'Bow'], ['crown', 'Crown'], ['bandana', 'Bandana'], ['glasses', 'Sunglasses'], ['flower', 'Flower'], ['headphones', 'Headphones']];
  const BOWLS = [['classic', 'Classic'], ['steel', 'Steel'], ['ceramic', 'Ceramic'], ['puppy', 'Puppy'], ['tub', 'Country Tub']];
  const POOPS = [['cute', 'Cute'], ['classic', 'Classic'], ['golden', 'Golden'], ['rainbow', 'Rainbow'], ['off', 'Off']];
  const TASKS = ['Pay rent', 'Water the plants', 'Book the dentist', 'Reply to emails', 'Ship the release', 'Call grandma', 'Do the laundry', 'Renew passport'];
  // Same spots the app uses (BowlView.swift), in bowl pixels from the top left.
  const PILE = [[10, 5.5, false], [16, 5.5, true], [13, 4.5, false], [7, 6, true], [19, 6, false]];
  const HANGS = [[15, 17], [23, 17], [19, 19], [13, 20], [25, 20], [19, 22]];
  const STACK = [[11, 31], [23, 31], [17, 31], [14, 29], [20, 29], [17, 27]];
  const GROUND = 30;

  const $ = (s) => document.querySelector(s);
  const el = (tag, cls, parent) => { const e = document.createElement(tag); if (cls) e.className = cls; if (parent) parent.appendChild(e); return e; };
  const pick = (a) => a[Math.floor(Math.random() * a.length)];
  const rand = (a, b) => a + Math.random() * (b - a);
  const store = {
    get(k) { try { return localStorage.getItem('treatly.' + k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem('treatly.' + k, v); } catch { /* private mode */ } },
  };

  const data = {};
  const sizes = {};
  const state = {
    pet: store.get('pet') || 'shiba',
    wear: store.get('wear') || 'none',
    bowl: store.get('bowl') || 'classic',
    poop: store.get('poop') || 'cute',
    music: false,
  };

  function loadImage(src) {
    return new Promise((res) => {
      const i = new Image();
      i.onload = () => { sizes[src] = [i.naturalWidth, i.naturalHeight]; res(); };
      i.onerror = () => { sizes[src] = [16, 16]; res(); };
      i.src = src;
    });
  }

  // An <img> drawn at a whole-pixel scale, positioned by its centre or bottom.
  function art(src, scale, parent) {
    const i = el('img', null, parent);
    const [w, h] = sizes[src] || [16, 16];
    i.src = src; i.alt = ''; i.width = w * scale; i.height = h * scale;
    return i;
  }

  // Sprite sheets: rows are animations, columns are frames. Wardrobe sheets share the layout.
  const sprites = new Set();
  class Sprite {
    constructor(id, scale) {
      // Packs can be drawn smaller or bigger than the usual 2.5x (the gorilla is smaller).
      this.d = data[id]; this.s = scale * (data[id].sheet.scale || 2.5) / 2.5;
      const sh = this.d.sheet;
      this.fw = sh.frameWidth; this.fh = sh.frameHeight;
      const anims = Object.values(sh.animations);
      const cols = Math.max(...anims.map((a) => a.count));
      const rows = Math.max(...anims.map((a) => a.row)) + 1;
      this.el = el('div', 'sprite');
      this.el.style.width = this.fw * this.s + 'px';
      this.el.style.height = this.fh * this.s + 'px';
      this.el.style.backgroundSize = `${cols * this.fw * this.s}px ${rows * this.fh * this.s}px`;
      this.wear(null);
      this.play('idle');
      sprites.add(this);
    }
    get w() { return this.fw * this.s; }
    get h() { return this.fh * this.s; }
    // `extra` goes on top of the chosen item, e.g. headphones while listening to music.
    wear(item, extra) {
      const has = (w) => w && w !== 'none' && (this.d.sheet.wardrobe || []).includes(w);
      const layers = [];
      if (has(extra) && extra !== item) layers.push(`url(pets/${this.d.id}/wear-${extra}.png)`);
      if (has(item)) layers.push(`url(pets/${this.d.id}/wear-${item}.png)`);
      layers.push(`url(pets/${this.d.id}/${this.d.sheet.image})`);
      this.el.style.backgroundImage = layers.join(',');
    }
    play(name) {
      if (this.anim === name) return;
      this.anim = name; this.t0 = performance.now();
    }
    tick(now) {
      const all = this.d.sheet.animations;
      const a = all[this.anim] || all.idle;
      const f = a.fps ? Math.floor(((now - this.t0) / 1000) * a.fps) % a.count : 0;
      const pos = `${-f * this.w}px ${-a.row * this.h}px`;
      if (pos !== this.pos) { this.pos = pos; this.el.style.backgroundPosition = pos; }
    }
    remove() { sprites.delete(this); this.el.remove(); }
  }
  function frame(now) { sprites.forEach((s) => s.tick(now)); requestAnimationFrame(frame); }

  const bowlArt = (style, back) => `art/bowl-${style}-appleReminders${back ? '-back' : ''}.png`;
  const treatArt = (id) => `pets/${id}/treat.png`;
  // Some pets hold their treat differently each time, e.g. the panda's bamboo at any angle.
  const heldList = (id) => (data[id].treat.heldImages || ['treat.png']).map((f) => `pets/${id}/${f}`);
  const poopArt = (style) => `art/poop-${style}.png`;
  // The gorilla's banana tree and the panda's bamboo pot stand in for the bowl.
  const kind = (id) => data[id].container || 'bowl';
  const isTree = (id) => kind(id) !== 'bowl';

  // A bowl (or tree) with up to `count` treats, at `scale` per art pixel.
  function container(id, style, count, scale, parent) {
    const box = el('div', 'bowlart', parent);
    if (isTree(id)) {
      const bamboo = kind(id) === 'bamboo';
      const tree = art(`art/${bamboo ? 'bamboo' : 'tree'}-appleReminders.png`, scale, box);
      box.style.width = tree.width + 'px'; box.style.height = tree.height + 'px';
      (bamboo ? STACK : HANGS).slice(0, count).forEach(([x, y], i) => placeTreat(box, id, x, y, scale, i % 2 === 1));
    } else {
      const back = art(bowlArt(style, true), scale, box);
      box.style.width = back.width + 'px'; box.style.height = back.height + 'px';
      PILE.slice(0, count).forEach(([x, y, flip]) => placeTreat(box, id, x, y, scale, flip));
      art(bowlArt(style, false), scale, box);
    }
    return box;
  }
  function placeTreat(box, id, x, y, scale, flip) {
    const t = art(treatArt(id), scale / 2, box);
    t.style.left = x * scale - t.width / 2 + 'px';
    t.style.top = y * scale - t.height / 2 + 'px';
    if (flip) t.style.transform = 'scaleX(-1)';
  }

  // ---------- The demo on the fake desktop ----------
  const stage = $('#stage');
  let gen = 0;
  let hero = null;
  class Cancelled extends Error {}

  const wait = (ms, g) => new Promise((res, rej) => setTimeout(() => (g === gen ? res() : rej(new Cancelled())), ms));

  function heroScale() { return stage.clientWidth < 600 ? 2.5 : 5; }

  function startHero() {
    gen += 1;
    const g = gen;
    if (hero) hero.sprite.remove();
    stage.replaceChildren();
    const id = state.pet;
    const S = heroScale();
    const sprite = new Sprite(id, S);
    sprite.wear(state.wear);
    const wrap = el('div', 'pet', stage);
    const body = el('div', 'body', wrap);
    body.appendChild(sprite.el);
    const mouth = data[id].sheet.mouth || [sprite.fw - 3, sprite.fh / 2];
    const carry = art(treatArt(id), S / 2.5, body);
    carry.className = 'carry';
    carry.style.left = mouth[0] * S - carry.width / 2 + 'px';
    carry.style.top = mouth[1] * S - carry.height / 2 + 'px';
    carry.hidden = true;
    wrap.style.bottom = GROUND - (data[id].sheet.footPadding || 0) * S + 'px';

    hero = {
      id, S, sprite, wrap, body, carry, g,
      x: sprite.w / 2 + 10, facing: 1, count: 3, task: 0,
      bubble: el('div', 'bubble', stage),
      menu: el('div', 'menu', stage),
      bowl: null, dropped: null,
    };
    if (state.music) {
      // Music on: it sits down with its headphones on and bobs along.
      sprite.wear(state.wear, 'headphones');
      sprite.play('sit');
      sprite.el.classList.add('bob');
      hero.x = stage.clientWidth * 0.35;
      setStep('');
      notes(stage, () => hero.x, GROUND + sprite.h);
    }
    hero.menu.innerHTML = '<div>Done</div><div>Snooze 10 min</div><div>Snooze 1 hour</div><hr><div>Next treat</div>';
    renderBowl();
    place();
    if (!state.music) loop(g).catch((e) => { if (!(e instanceof Cancelled)) throw e; });
  }

  // Picks how the treat is held this time and centres it on the mouth (or paws).
  function holdTreat() {
    const src = pick(heldList(hero.id));
    const [w, h] = sizes[src] || [16, 16];
    const ts = hero.S / 2.5;
    const mouth = data[hero.id].sheet.mouth || [hero.sprite.fw - 3, hero.sprite.fh / 2];
    Object.assign(hero.carry, { src, width: w * ts, height: h * ts });
    hero.carry.style.left = mouth[0] * hero.S - (w * ts) / 2 + 'px';
    hero.carry.style.top = mouth[1] * hero.S - (h * ts) / 2 + 'px';
  }

  // Music notes floating up beside a listening pet; `x` and `y` give where.
  function notes(parent, x, y) {
    // \uFE0E asks for the plain text note, not an emoji tile.
    ['♪\uFE0E', '♫\uFE0E', '♪\uFE0E', '♫\uFE0E'].forEach((n, i) => {
      const note = el('span', 'music-note', parent);
      note.textContent = n;
      note.style.animationDelay = i * 0.6 + 's';
      note.style.left = x() + (i % 2 ? 1 : -1) * (24 + i * 6) + 'px';
      note.style.bottom = y - 10 + 'px';
    });
  }

  function renderBowl() {
    if (!hero) return;
    if (hero.bowl) hero.bowl.remove();
    const scale = hero.S * 0.8;
    hero.bowl = container(hero.id, state.bowl, hero.count, scale, stage);
    hero.bowl.classList.add('bowl');
    hero.bowl.style.bottom = GROUND + 'px';
    hero.bowl.style.left = bowlLeft() + 'px';
  }
  const bowlWidth = () => ({ tree: 38, bamboo: 34 }[kind(hero.id)] || 26) * hero.S * 0.8;
  const bowlLeft = () => stage.clientWidth * 0.86 - bowlWidth();
  // Where the pet stands to reach into the bowl.
  const bowlSpot = () => bowlLeft() + bowlWidth() * (isTree(hero.id) ? 0.3 : 0.1) - hero.sprite.w * 0.4;

  function place() {
    hero.wrap.style.transform = `translateX(${hero.x - hero.sprite.w / 2}px)`;
    hero.body.classList.toggle('left', hero.facing < 0);
    positionBubble();
  }
  function positionBubble() {
    const b = hero.bubble;
    if (!b.classList.contains('show')) return;
    const W = stage.clientWidth;
    const bw = b.offsetWidth;
    b.style.left = Math.max(8, Math.min(W - bw - 8, hero.x - bw / 2)) + 'px';
    b.style.bottom = GROUND + hero.sprite.h + 4 + 'px';
  }
  function say(text, kind = '') {
    const b = hero.bubble;
    if (!text) { b.classList.remove('show'); return; }
    b.textContent = text;
    b.className = 'bubble show ' + kind;
    positionBubble();
  }
  function fill(phrases, task) {
    return pick(phrases || ['{task}']).replaceAll('{task}', task).replaceAll('{name}', data[hero.id].defaultName);
  }
  function setStep(name) {
    document.querySelectorAll('#steps li').forEach((li) => {
      li.classList.toggle('on', li.dataset.step === name);
      if (li.dataset.step === 'done') li.textContent = name === 'snooze' ? 'Snooze' : 'Done';
      if (name === 'snooze' && li.dataset.step === 'done') li.classList.add('on');
    });
  }

  function walkTo(x, g, run = false) {
    const p = data[hero.id].personality;
    const speed = run ? p.runSpeed * 1.4 : p.walkSpeed * 2.2;
    const scale = hero.S / 5;
    hero.facing = x >= hero.x ? 1 : -1;
    hero.sprite.play(run ? 'run' : 'walk');
    return new Promise((res, rej) => {
      let last = performance.now();
      const step = (now) => {
        if (g !== gen) return rej(new Cancelled());
        const dt = Math.min(0.05, (now - last) / 1000);
        last = now;
        const d = x - hero.x;
        const m = speed * scale * dt;
        if (Math.abs(d) <= m) { hero.x = x; place(); hero.sprite.play('idle'); return res(); }
        hero.x += Math.sign(d) * m;
        place();
        requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    });
  }

  function onGround(src, x, scale) {
    const i = art(src, scale, stage);
    i.classList.add('ground-thing');
    i.style.left = x - i.width / 2 + 'px';
    i.style.bottom = GROUND - 1 + 'px';
    return i;
  }

  async function showMenu(index, g) {
    const m = hero.menu;
    const W = stage.clientWidth;
    m.style.left = Math.min(W - 170, hero.x + hero.sprite.w * 0.2) + 'px';
    m.style.bottom = GROUND + hero.sprite.h * 0.3 + 'px';
    [...m.querySelectorAll('div')].forEach((d) => d.classList.remove('hot'));
    m.classList.add('show');
    await wait(700, g);
    m.querySelectorAll('div')[index].classList.add('hot');
    await wait(550, g);
    m.classList.remove('show');
  }

  async function loop(g) {
    const ph = data[hero.id].phrases;
    const W = () => stage.clientWidth;
    const treatScale = hero.S / 2.5;
    let round = 0;
    for (;;) {
      if (hero.count === 0) { hero.count = 3; renderBowl(); }
      const task = TASKS[hero.task++ % TASKS.length];

      setStep('fetch'); say(null);
      await walkTo(bowlSpot(), g);
      hero.facing = 1; place();
      hero.sprite.play(kind(hero.id) === 'tree' ? 'beg' : 'sit');
      await wait(700, g);
      hero.count -= 1; renderBowl();
      holdTreat();
      hero.carry.hidden = false;

      setStep('carry');
      say(fill(ph.carry, task));
      await walkTo(rand(W() * 0.18, W() * 0.5), g, true);
      hero.facing = 1; place();
      hero.sprite.play('idle');
      await wait(1300, g);

      setStep('drop');
      hero.carry.hidden = true;
      hero.dropped = onGround(treatArt(hero.id), hero.x + hero.sprite.w * 0.45, treatScale);
      hero.sprite.play('sit');
      say(fill(ph.drop, task));
      await wait(2300, g);

      setStep('yell');
      hero.sprite.play('bark');
      say(fill(ph.yell, task), 'yell');
      await wait(2400, g);

      setStep('whine');
      hero.sprite.play('beg');
      say(fill(ph.whine, task), 'whine');
      await wait(2400, g);

      say(null);
      const snooze = ++round % 3 === 0;
      await showMenu(snooze ? 1 : 0, g);
      const treat = hero.dropped;
      if (snooze) {
        setStep('snooze');
        treat.classList.add('bury');
        hero.sprite.play('sit');
        say(fill(ph.bury, task));
        await wait(2200, g);
      } else {
        setStep('done');
        treat.classList.add('gone');
        hero.sprite.play('sit');
        say(fill(ph.happy, task), 'happy');
        await wait(1800, g);
        if (state.poop !== 'off') {
          const poop = onGround(poopArt(state.poop), hero.x - hero.sprite.w * 0.35, treatScale);
          setTimeout(() => poop.classList.add('gone'), 6000);
          setTimeout(() => poop.remove(), 7000);
        }
      }
      setTimeout(() => treat.remove(), 1500);
      hero.dropped = null;
      say(null);
      setStep('');
      await walkTo(rand(W() * 0.55, W() * 0.65), g);
      if (data[hero.id].sheet.animations.trick && Math.random() < 0.6) {
        // Playful pets show off their special move just for fun.
        hero.sprite.play('trick');
        say(fill(data[hero.id].phrases.trick, task), 'yell');
        await wait(4000, g);
        say(null);
        hero.sprite.play('idle');
      } else {
        hero.sprite.play(Math.random() < 0.3 ? 'sleep' : 'idle');
      }
      await wait(1800, g);
    }
  }

  // ---------- Pickers ----------
  function chips(container, items, key, onPick, decorate) {
    const root = $(container);
    root.replaceChildren();
    items.forEach(([value, label]) => {
      const b = el('button', 'chip', root);
      b.type = 'button';
      b.dataset.value = value;
      if (decorate) decorate(b, value);
      el('span', null, b).textContent = label;
      b.addEventListener('click', () => {
        state[key] = value; store.set(key, value);
        refreshChips();
        onPick(value);
      });
    });
  }
  function refreshChips() {
    const groups = { '#pick-pet': 'pet', '#pick-wear': 'wear', '#pick-bowl': 'bowl', '#pick-poop': 'poop' };
    Object.entries(groups).forEach(([sel, key]) => {
      document.querySelectorAll(sel + ' .chip').forEach((c) => c.setAttribute('aria-pressed', String(c.dataset.value === state[key])));
    });
    const tree = isTree(state.pet);
    document.querySelectorAll('#pick-bowl .chip').forEach((c) => { c.disabled = tree; });
    document.querySelectorAll('.pet-card').forEach((c) => c.setAttribute('aria-pressed', String(c.dataset.pet === state.pet)));
  }
  function choosePet(id) {
    state.pet = id; store.set('pet', id);
    refreshChips();
    startHero();
  }

  function buildPickers() {
    chips('#pick-pet', PETS.map((id) => [id, data[id].name]), 'pet', () => startHero());
    chips('#pick-wear', WEAR, 'wear', (w) => {
      if (hero) hero.sprite.wear(w);
      gallerySprites.forEach((s) => s.wear(w));
    });
    chips('#pick-bowl', BOWLS, 'bowl', () => renderBowl(), (b, style) => {
      const box = el('span', 'bowlart', b);
      [true, false].forEach((back) => art(bowlArt(style, back), 1, box));
      box.style.width = '26px'; box.style.height = '17px';
    });
    chips('#pick-poop', POOPS, 'poop', () => {}, (b, style) => {
      if (style !== 'off') art(poopArt(style), 1, b);
    });
    const music = el('button', 'chip', $('#pick-music'));
    music.type = 'button';
    const label = () => { music.textContent = state.music ? '⏸ Stop the music' : '🎵 Play some music'; music.setAttribute('aria-pressed', String(state.music)); };
    music.addEventListener('click', () => { state.music = !state.music; label(); startHero(); });
    label();
    refreshChips();
  }

  // ---------- Gallery and How it works ----------
  const gallerySprites = [];
  function buildGallery() {
    const root = $('#gallery');
    PETS.forEach((id) => {
      const d = data[id];
      const card = el('div', 'pet-card', root);
      card.setAttribute('role', 'button');
      card.tabIndex = 0;
      card.dataset.pet = id;
      const s = new Sprite(id, 3);
      s.wear(state.wear);
      gallerySprites.push(s);
      el('div', 'art', card).appendChild(s.el);
      el('h3', null, card).textContent = `${d.name}`;
      const meta = el('div', 'meta', card);
      meta.append(`${d.defaultName} · loves ${d.treat.name} `);
      art(treatArt(id), 1, meta);
      el('p', 'meta', card).textContent = PERSONALITY[id] || '';
      el('p', 'say', card).textContent = '"' + pick(d.phrases.yell).replaceAll('{task}', 'Pay rent').replaceAll('{name}', d.defaultName) + '"';
      card.addEventListener('mouseenter', () => s.play('bark'));
      card.addEventListener('mouseleave', () => s.play('idle'));
      const adopt = () => {
        choosePet(id);
        $('.hero').scrollIntoView({ behavior: 'smooth' });
      };
      card.addEventListener('click', adopt);
      card.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); adopt(); } });
    });
  }

  function buildHow() {
    container('shiba', 'classic', 5, 3, $('#how-bowl'));

    const nag = new Sprite('husky', 2.5);
    nag.play('bark');
    $('#how-nag').appendChild(nag.el);

    const done = new Sprite('golden', 2.5);
    done.play('sit');
    $('#how-done').appendChild(done.el);
    art(poopArt('cute'), 2, $('#how-done'));

    const snooze = new Sprite('black-cat', 2.5);
    snooze.play('sleep');
    $('#how-snooze').appendChild(snooze.el);
  }

  function buildQuirks() {
    const listen = new Sprite('shiba', 2.5);
    listen.wear(null, 'headphones');
    listen.play('sit');
    listen.el.classList.add('bob');
    $('#quirk-music').appendChild(listen.el);
    notes($('#quirk-music'), () => $('#quirk-music').clientWidth / 2, 50);

    const panda = new Sprite('panda', 2.5);
    panda.play('fall');
    $('#quirk-trip').appendChild(panda.el);

    const tree = art('art/tree-appleReminders.png', 1.6, $('#quirk-swing'));
    tree.classList.add('quirk-tree');
    const swinger = new Sprite('mighty', 2);
    swinger.play('swing');
    swinger.el.classList.add('quirk-swinger');
    $('#quirk-swing').appendChild(swinger.el);

    const show = new Sprite('mighty', 2);
    show.play('trick');
    $('#quirk-show').appendChild(show.el);

    const dozy = new Sprite('shiba', 2.5);
    dozy.play('sleep');
    $('#quirk-battery').appendChild(dozy.el);
    const batt = el('div', 'quirk-batt');
    batt.setAttribute('aria-hidden', 'true');
    $('#quirk-battery').appendChild(batt);
  }

  // ---------- Bits ----------
  document.querySelectorAll('.copy').forEach((b) => b.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(b.dataset.copy); b.textContent = 'Copied!'; } catch { b.textContent = 'Select & copy'; }
    setTimeout(() => { b.textContent = 'Copy'; }, 1600);
  }));
  function clock() {
    const d = new Date();
    $('#clock').textContent = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  }

  let lastWidth = 0;
  let resizeTimer = 0;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      const w = stage.clientWidth;
      if (Math.abs(w - lastWidth) > 40) { lastWidth = w; startHero(); }
    }, 250);
  });

  async function main() {
    const packs = await Promise.all(PETS.map((id) => fetch(`pets/${id}/pet.json`).then((r) => r.json())));
    packs.forEach((p) => { data[p.id] = p; });
    if (!data[state.pet]) state.pet = 'shiba';
    const images = [];
    PETS.forEach((id) => images.push(treatArt(id), ...heldList(id)));
    BOWLS.forEach(([s]) => images.push(bowlArt(s, true), bowlArt(s, false)));
    POOPS.forEach(([s]) => { if (s !== 'off') images.push(poopArt(s)); });
    images.push('art/tree-appleReminders.png', 'art/bamboo-appleReminders.png');
    await Promise.all(images.map(loadImage));

    buildPickers();
    buildGallery();
    buildHow();
    buildQuirks();
    refreshChips();
    clock(); setInterval(clock, 30000);
    lastWidth = stage.clientWidth;
    startHero();
    requestAnimationFrame(frame);
  }
  main();
})();
