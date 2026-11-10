/* NAXÇIVAN GÖYƏRÇİN — live social layer (additive V3 module) */
(function () {
  "use strict";

  const cfg = window.NG_SUPABASE_CONFIG || {};
  const sdk = window.supabase;
  const configured = /^https:\/\/[A-Za-z0-9-]+\.supabase\.co$/.test(cfg.url || "") &&
    typeof cfg.publishableKey === "string" &&
    cfg.publishableKey.length > 20 &&
    !cfg.publishableKey.includes("service_role") &&
    !cfg.publishableKey.startsWith("sb_secret_");

  let client = null;
  let currentUser = null;
  let profile = null;
  let ready = false;
  let activeConversation = null;
  let messageChannel = null;
  let feedChannel = null;
  let authMode = "signin";
  let activeTab = "feed";

  const $ = (id) => document.getElementById(id);
  const esc = (value) => String(value == null ? "" : value).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  }[c]));
  const when = (value) => {
    try { return new Date(value).toLocaleString(); } catch (_) { return ""; }
  };
  const main = () => $("mainViewport");
  const modal = (html) => {
    const overlay = $("modalOverlay"), box = $("modalContainer");
    if (!overlay || !box) return;
    box.innerHTML = html;
    overlay.classList.remove("hidden");
  };
  const closeModal = () => {
    if (typeof window.closeModal === "function") window.closeModal();
    else $("modalOverlay")?.classList.add("hidden");
  };

  function ensureStatus() {
    if (!$("ngLiveStatus")) {
      const el = document.createElement("div");
      el.id = "ngLiveStatus";
      el.className = "mx-3 mt-3 mb-1 rounded-xl border px-3 py-2 text-xs";
      el.style.cssText = "border-color:#2A364F;background:#121820;color:#9AA8B8";
      const header = document.querySelector("#app > header");
      if (header) header.insertAdjacentElement("afterend", el);
    }
    const actions = document.querySelector("header > div:last-child");
    if (actions && !$("ngAuthAction")) {
      const button = document.createElement("button");
      button.id = "ngAuthAction";
      button.type = "button";
      button.className = "px-3 py-2 rounded-xl text-xs font-bold border";
      button.style.cssText = "border-color:#19C7C7;color:#19C7C7;background:#121820";
      button.textContent = "Hesab";
      button.addEventListener("click", () => {
        if (!configured || !client) showSetup();
        else if (currentUser) window.openTab("profile");
        else openAuth("signin");
      });
      actions.prepend(button);
    }
  }

  function setStatus(message, kind) {
    ensureStatus();
    const el = $("ngLiveStatus");
    if (!el) return;
    const colors = {
      live: ["#19C7C7", "rgba(25,199,199,.08)"],
      warn: ["#f0c36d", "rgba(240,195,109,.08)"],
      error: ["#ff8585", "rgba(255,100,100,.08)"],
      info: ["#9AA8B8", "#121820"]
    };
    const pair = colors[kind || "info"];
    el.style.borderColor = pair[0];
    el.style.background = pair[1];
    el.style.color = pair[0];
    el.textContent = message;
    const b = $("ngAuthAction");
    if (b) b.textContent = currentUser ? "Profil" : "Daxil ol";
  }

  function showSetup() {
    ensureStatus();
    setStatus("BACKEND QURULMAYIB — canlı hesablar, paylaşımlar və mesajlar hələ aktiv deyil.", "warn");
    if (main()) main().innerHTML = `
      <section class="p-4 space-y-3">
        <div class="rounded-2xl border p-4 space-y-2" style="border-color:#2A364F;background:#121820">
          <h2 class="font-bold text-lg" style="color:#19C7C7">Canlı sosial şəbəkə bağlantısı</h2>
          <p class="text-sm">Bu səhifə real istifadəçi məlumatı göstərmir, çünki Supabase bağlantısı qurulmayıb.</p>
          <ol class="list-decimal pl-5 text-xs space-y-2" style="color:#9AA8B8">
            <li>Supabase-də yeni layihə yaradın.</li>
            <li>Əvvəl <code>20261110000000_v3_foundation.sql</code>, sonra <code>20261110010000_v3_realtime.sql</code> migration faylını SQL Editor-də tətbiq edin.</li>
            <li><code>site/supabase-config.js</code> faylında Project URL və yalnız publishable/anon public key daxil edin.</li>
            <li>Bu branch-i GitHub Pages-ə yerləşdirin. Heç vaxt service_role/secret key istifadə etməyin.</li>
          </ol>
          <p class="text-xs" style="color:#f0c36d">Mövcud dizayn və digər bölmələr saxlanılıb. Real backend aktivləşənədək bu modul demo istifadəçiləri real hesab kimi göstərmir.</p>
        </div>
      </section>`;
  }

  function showLoading(message) {
    if (main()) main().innerHTML = `<div class="p-6 text-center text-sm" style="color:#9AA8B8">${esc(message || "Bağlantı yoxlanılır...")}</div>`;
  }

  function openAuth(mode) {
    authMode = mode || "signin";
    const signup = authMode === "signup";
    modal(`
      <div class="p-4 space-y-3">
        <div class="flex items-center justify-between">
          <h3 class="font-bold text-base">${signup ? "Yeni hesab yarat" : "Hesaba daxil ol"}</h3>
          <button type="button" id="ngAuthClose" class="text-xl" aria-label="Bağla">×</button>
        </div>
        <form id="ngAuthForm" class="space-y-3">
          ${signup ? `<label class="block text-xs">Görünən ad<input id="ngDisplayName" class="modal-field mt-1" required maxlength="80" autocomplete="name"></label>
          <label class="block text-xs">İstifadəçi adı<input id="ngUsername" class="modal-field mt-1" required minlength="3" maxlength="30" pattern="[A-Za-z0-9_]+" autocomplete="username"></label>` : ""}
          <label class="block text-xs">E-poçt<input id="ngEmail" type="email" class="modal-field mt-1" required autocomplete="email"></label>
          <label class="block text-xs">Şifrə<input id="ngPassword" type="password" class="modal-field mt-1" required minlength="8" autocomplete="${signup ? "new-password" : "current-password"}"></label>
          <button class="market-action market-primary w-full" type="submit">${signup ? "Qeydiyyatdan keç" : "Daxil ol"}</button>
        </form>
        <button type="button" id="ngAuthSwitch" class="text-xs w-full text-center" style="color:#19C7C7">${signup ? "Artıq hesabınız var? Daxil olun" : "Hesabınız yoxdur? Qeydiyyatdan keçin"}</button>
        <p id="ngAuthError" class="text-xs" style="color:#ff8585" role="status"></p>
        <p class="text-[10px]" style="color:#9AA8B8">E-poçt təsdiqi Supabase layihənizin Auth ayarlarından asılıdır.</p>
      </div>`);
    $("ngAuthClose")?.addEventListener("click", closeModal);
    $("ngAuthSwitch")?.addEventListener("click", () => openAuth(signup ? "signin" : "signup"));
    $("ngAuthForm")?.addEventListener("submit", submitAuth);
  }

  async function submitAuth(event) {
    event.preventDefault();
    const errorBox = $("ngAuthError");
    const email = $("ngEmail")?.value.trim();
    const password = $("ngPassword")?.value || "";
    if (!email || password.length < 8) {
      if (errorBox) errorBox.textContent = "Düzgün e-poçt və ən azı 8 simvolluq şifrə daxil edin.";
      return;
    }
    const button = $("ngAuthForm")?.querySelector('button[type="submit"]');
    if (button) button.disabled = true;
    try {
      if (authMode === "signup") {
        const displayName = $("ngDisplayName")?.value.trim();
        const username = $("ngUsername")?.value.trim().toLowerCase();
        if (!displayName || !/^[a-z0-9_]{3,30}$/.test(username || "")) throw new Error("İstifadəçi adı 3–30 simvol olmalı; yalnız a-z, 0-9 və _ istifadə edilməlidir.");
        const { data, error } = await client.auth.signUp({
          email, password, options: { data: { display_name: displayName } }
        });
        if (error) throw error;
        if (data.session && data.user) {
          const { error: profileError } = await client.from("profiles").update({
            username, display_name: displayName
          }).eq("id", data.user.id);
          if (profileError) throw profileError;
          currentUser = data.user;
          await loadProfile();
          closeModal();
          setStatus("Hesab yaradıldı. Canlı sosial şəbəkəyə qoşuldunuz.", "live");
          renderCurrent();
        } else {
          if (errorBox) errorBox.textContent = "Qeydiyyat yaradıldı. E-poçtunuza gələn təsdiq linkini açın, sonra daxil olun.";
        }
      } else {
        const { data, error } = await client.auth.signInWithPassword({ email, password });
        if (error) throw error;
        currentUser = data.user;
        await loadProfile();
        closeModal();
        setStatus("Hesaba təhlükəsiz giriş edildi.", "live");
        renderCurrent();
      }
    } catch (error) {
      if (errorBox) errorBox.textContent = error.message || "Giriş əməliyyatı alınmadı.";
    } finally {
      if (button) button.disabled = false;
    }
  }

  async function loadProfile() {
    if (!currentUser) { profile = null; return; }
    const { data, error } = await client.from("profiles")
      .select("id,username,display_name,bio,avatar_path,city,locale,created_at")
      .eq("id", currentUser.id).single();
    if (error) throw error;
    profile = data;
  }

  function avatarUrl(path) {
    if (!path || !client) return "";
    return client.storage.from("public-media").getPublicUrl(path).data.publicUrl;
  }

  function renderCurrent() {
    const tab = activeTab || "feed";
    if (["feed", "profile", "messages"].includes(tab)) renderTab(tab);
  }

  function renderTab(tab) {
    if (!configured || !client) { showSetup(); return; }
    if (!ready) { showLoading("Supabase bağlantısı qurulur..."); return; }
    if (tab === "feed") renderFeed();
    else if (tab === "profile") renderProfile();
    else if (tab === "messages") renderMessages();
  }

  async function renderFeed() {
    const host = main();
    if (!host) return;
    host.innerHTML = `<div class="p-5 text-center text-sm" style="color:#9AA8B8">Canlı paylaşımlar yüklənir...</div>`;
    try {
      const { data: posts, error } = await client.from("posts")
        .select("id,author_id,body,visibility,created_at")
        .order("created_at", { ascending: false }).limit(50);
      if (error) throw error;
      const ids = [...new Set((posts || []).map(p => p.author_id))];
      const postIds = (posts || []).map(p => p.id);
      const [{ data: profiles, error: pErr }, { data: media, error: mErr }] = await Promise.all([
        ids.length ? client.from("profiles").select("id,username,display_name,avatar_path").in("id", ids) : Promise.resolve({ data: [], error: null }),
        postIds.length ? client.from("post_media").select("post_id,storage_path,media_type,alt_text,sort_order").in("post_id", postIds).order("sort_order") : Promise.resolve({ data: [], error: null })
      ]);
      if (pErr) throw pErr;
      if (mErr) throw mErr;
      const byId = new Map((profiles || []).map(p => [p.id, p]));
      const byPost = new Map();
      (media || []).forEach(m => {
        if (!byPost.has(m.post_id)) byPost.set(m.post_id, []);
        byPost.get(m.post_id).push(m);
      });
      host.innerHTML = `
        <section class="p-3 space-y-3">
          <div class="flex items-center justify-between">
            <div><h2 class="font-extrabold text-lg" style="color:#19C7C7">Canlı göyərçin icması</h2><p class="text-[10px]" style="color:#9AA8B8">Serverdən yüklənən real paylaşımlar</p></div>
            <span class="sample-tag">SUPABASE LIVE</span>
          </div>
          ${currentUser ? `<button id="ngComposeOpen" class="w-full rounded-xl p-3 text-left text-xs border" style="background:#121820;border-color:#2A364F;color:#9AA8B8">Göyərçinləriniz haqqında paylaşım yazın...</button>` : `<button id="ngLoginFromFeed" class="w-full rounded-xl p-3 text-xs font-bold" style="background:#19C7C7;color:#061315">Paylaşmaq üçün daxil olun</button>`}
          ${(posts || []).length ? posts.map(post => {
            const author = byId.get(post.author_id) || {};
            const files = byPost.get(post.id) || [];
            const avatar = avatarUrl(author.avatar_path);
            const mediaHtml = files.map(file => {
              const url = client.storage.from("public-media").getPublicUrl(file.storage_path).data.publicUrl;
              return file.media_type === "video"
                ? `<video class="post-media" controls playsinline preload="metadata" src="${esc(url)}"></video>`
                : `<img class="post-media" loading="lazy" src="${esc(url)}" alt="${esc(file.alt_text || "Göyərçin paylaşımı")}">`;
            }).join("");
            return `<article class="rounded-2xl border p-3 space-y-3" style="background:#121820;border-color:#2A364F">
              <div class="flex items-center gap-2">
                ${avatar ? `<img src="${esc(avatar)}" class="w-9 h-9 rounded-full object-cover" alt="">` : `<div class="w-9 h-9 rounded-full flex items-center justify-center" style="background:#1A2230">🕊️</div>`}
                <div class="min-w-0"><b class="text-xs">${esc(author.display_name || "İstifadəçi")}</b><div class="text-[10px]" style="color:#9AA8B8">@${esc(author.username || "user")} · ${esc(when(post.created_at))}</div></div>
              </div>
              <p class="text-sm whitespace-pre-wrap break-words">${esc(post.body)}</p>
              ${mediaHtml}
              <div class="text-[10px]" style="color:#9AA8B8">İctimai paylaşım · ${esc(post.visibility)}</div>
            </article>`;
          }).join("") : `<div class="rounded-2xl border p-6 text-center text-sm" style="background:#121820;border-color:#2A364F;color:#9AA8B8">Hələ paylaşım yoxdur. İlk real göyərçin paylaşımını siz edin.</div>`}
        </section>`;
      $("ngComposeOpen")?.addEventListener("click", openComposer);
      $("ngLoginFromFeed")?.addEventListener("click", () => openAuth("signin"));
    } catch (error) {
      host.innerHTML = `<div class="p-4 text-sm" style="color:#ff8585">Canlı lent yüklənmədi: ${esc(error.message)}</div>`;
    }
  }

  function openComposer() {
    if (!currentUser) { openAuth("signin"); return; }
    modal(`
      <div class="p-4 space-y-3">
        <div class="flex justify-between"><h3 class="font-bold">Canlı paylaşım yarat</h3><button id="ngComposeClose" type="button">×</button></div>
        <textarea id="ngPostBody" class="modal-field" rows="4" maxlength="10000" placeholder="Göyərçin, kümes, uçuş və ya damazlıq təcrübənizi paylaşın..."></textarea>
        <label class="block text-xs">Şəkil və ya video (maksimum 50 MB)<input id="ngPostFile" type="file" accept="image/jpeg,image/png,image/webp,image/gif,video/mp4,video/webm" class="block w-full mt-2 text-xs"></label>
        <button id="ngPublishPost" class="market-action market-primary w-full" type="button">Serverdə paylaş</button>
        <p id="ngPostError" class="text-xs" style="color:#ff8585"></p>
      </div>`);
    $("ngComposeClose")?.addEventListener("click", closeModal);
    $("ngPublishPost")?.addEventListener("click", publishPost);
  }

  async function publishPost() {
    const button = $("ngPublishPost"), errorBox = $("ngPostError");
    const body = $("ngPostBody")?.value.trim() || "";
    const file = $("ngPostFile")?.files?.[0] || null;
    if (!body && !file) { if (errorBox) errorBox.textContent = "Mətn və ya media faylı əlavə edin."; return; }
    if (body.length > 10000) { if (errorBox) errorBox.textContent = "Mətn 10.000 simvoldan çox ola bilməz."; return; }
    const allowed = ["image/jpeg", "image/png", "image/webp", "image/gif", "video/mp4", "video/webm"];
    if (file && (!allowed.includes(file.type) || file.size > 50 * 1024 * 1024)) {
      if (errorBox) errorBox.textContent = "Yalnız JPG, PNG, WEBP, GIF, MP4 və WEBM; maksimum 50 MB.";
      return;
    }
    if (button) button.disabled = true;
    let postId = null, uploadedPath = null;
    try {
      const { data: post, error } = await client.from("posts").insert({
        author_id: currentUser.id, body, visibility: "public"
      }).select("id").single();
      if (error) throw error;
      postId = post.id;
      if (file) {
        const ext = file.name.split(".").pop().toLowerCase().replace(/[^a-z0-9]/g, "") || "bin";
        uploadedPath = `${currentUser.id}/posts/${crypto.randomUUID()}.${ext}`;
        const { error: uploadError } = await client.storage.from("public-media")
          .upload(uploadedPath, file, { contentType: file.type, upsert: false });
        if (uploadError) throw uploadError;
        const { error: mediaError } = await client.from("post_media").insert({
          post_id: postId, storage_path: uploadedPath,
          media_type: file.type.startsWith("video/") ? "video" : "image",
          alt_text: "NAXÇIVAN GÖYƏRÇİN paylaşım mediası"
        });
        if (mediaError) throw mediaError;
      }
      closeModal();
      setStatus("Paylaşım serverdə yaradıldı və lentə göndərildi.", "live");
      await renderFeed();
    } catch (error) {
      if (uploadedPath) await client.storage.from("public-media").remove([uploadedPath]).catch(() => {});
      if (postId) await client.from("posts").delete().eq("id", postId).catch(() => {});
      if (errorBox) errorBox.textContent = error.message || "Paylaşım alınmadı.";
      if (button) button.disabled = false;
    }
  }

  function renderProfile() {
    const host = main();
    if (!host) return;
    if (!currentUser || !profile) {
      host.innerHTML = `<div class="p-5 text-center space-y-3"><h2 class="font-bold text-lg">Şəxsi profil</h2><p class="text-sm" style="color:#9AA8B8">Öz profilinizi görmək üçün daxil olun.</p><button id="ngProfileLogin" class="market-action market-primary">Daxil ol / Qeydiyyat</button></div>`;
      $("ngProfileLogin")?.addEventListener("click", () => openAuth("signin"));
      return;
    }
    const avatar = avatarUrl(profile.avatar_path);
    host.innerHTML = `
      <section class="p-4 space-y-4">
        <div class="rounded-2xl border p-4 space-y-3" style="background:#121820;border-color:#2A364F">
          <div class="flex items-center gap-3">
            ${avatar ? `<img src="${esc(avatar)}" class="w-16 h-16 rounded-full object-cover" alt="">` : `<div class="w-16 h-16 rounded-full flex items-center justify-center text-2xl" style="background:#1A2230">🕊️</div>`}
            <div><h2 class="font-extrabold text-lg">${esc(profile.display_name)}</h2><p class="text-xs" style="color:#19C7C7">@${esc(profile.username)}</p><p class="text-[10px]" style="color:#9AA8B8">${esc(profile.city || "Şəhər qeyd edilməyib")}</p></div>
          </div>
          <p class="text-sm whitespace-pre-wrap">${esc(profile.bio || "Haqqında məlumat əlavə edilməyib.")}</p>
          <div class="flex gap-2"><button id="ngEditProfile" class="market-action market-primary flex-1">Profili redaktə et</button><button id="ngSignOut" class="market-action market-secondary">Çıxış</button></div>
        </div>
        <p class="text-[10px]" style="color:#9AA8B8">Hesab Supabase Auth ilə idarə olunur. Profil məlumatları serverdə saxlanılır.</p>
      </section>`;
    $("ngEditProfile")?.addEventListener("click", openProfileEditor);
    $("ngSignOut")?.addEventListener("click", signOut);
  }

  function openProfileEditor() {
    if (!profile) return;
    modal(`
      <div class="p-4 space-y-3">
        <div class="flex justify-between"><h3 class="font-bold">Şəxsi profili redaktə et</h3><button id="ngProfileClose" type="button">×</button></div>
        <label class="block text-xs">Görünən ad<input id="ngEditName" class="modal-field mt-1" maxlength="80" value="${esc(profile.display_name)}"></label>
        <label class="block text-xs">İstifadəçi adı<input id="ngEditUsername" class="modal-field mt-1" maxlength="30" value="${esc(profile.username)}"></label>
        <label class="block text-xs">Haqqımda<textarea id="ngEditBio" class="modal-field mt-1" rows="3" maxlength="500">${esc(profile.bio || "")}</textarea></label>
        <label class="block text-xs">Şəhər<input id="ngEditCity" class="modal-field mt-1" maxlength="100" value="${esc(profile.city || "")}"></label>
        <label class="block text-xs">Profil şəkli<input id="ngAvatarFile" class="block w-full mt-1 text-xs" type="file" accept="image/jpeg,image/png,image/webp"></label>
        <button id="ngSaveProfile" class="market-action market-primary w-full" type="button">Serverdə saxla</button>
        <p id="ngProfileError" class="text-xs" style="color:#ff8585"></p>
      </div>`);
    $("ngProfileClose")?.addEventListener("click", closeModal);
    $("ngSaveProfile")?.addEventListener("click", saveProfile);
  }

  async function saveProfile() {
    const button = $("ngSaveProfile"), errorBox = $("ngProfileError");
    const username = $("ngEditUsername")?.value.trim().toLowerCase() || "";
    const displayName = $("ngEditName")?.value.trim() || "";
    const bio = $("ngEditBio")?.value.trim() || "";
    const city = $("ngEditCity")?.value.trim() || "";
    const file = $("ngAvatarFile")?.files?.[0] || null;
    if (!/^[a-z0-9_]{3,30}$/.test(username) || !displayName) {
      if (errorBox) errorBox.textContent = "İstifadəçi adı 3–30 simvol, yalnız a-z, 0-9 və _ olmalıdır.";
      return;
    }
    if (button) button.disabled = true;
    let avatarPath = profile.avatar_path;
    try {
      if (file) {
        if (!["image/jpeg", "image/png", "image/webp"].includes(file.type) || file.size > 5 * 1024 * 1024) throw new Error("Profil şəkli JPG/PNG/WEBP və maksimum 5 MB olmalıdır.");
        avatarPath = `${currentUser.id}/avatars/${crypto.randomUUID()}.${file.name.split(".").pop().toLowerCase()}`;
        const { error } = await client.storage.from("public-media").upload(avatarPath, file, { contentType: file.type, upsert: false });
        if (error) throw error;
      }
      const { error } = await client.from("profiles").update({
        username, display_name: displayName, bio, city, avatar_path: avatarPath
      }).eq("id", currentUser.id);
      if (error) throw error;
      await loadProfile();
      closeModal();
      setStatus("Şəxsi profil serverdə yeniləndi.", "live");
      renderProfile();
    } catch (error) {
      if (errorBox) errorBox.textContent = error.message || "Profil saxlanmadı.";
      if (button) button.disabled = false;
    }
  }

  async function signOut() {
    const { error } = await client.auth.signOut();
    if (error) { setStatus("Çıxış alınmadı: " + error.message, "error"); return; }
    currentUser = null; profile = null; activeConversation = null;
    if (messageChannel) { await client.removeChannel(messageChannel); messageChannel = null; }
    setStatus("Hesabdan çıxış edildi.", "info");
    window.openTab("feed");
  }

  async function renderMessages() {
    const host = main();
    if (!host) return;
    if (!currentUser) {
      host.innerHTML = `<div class="p-5 text-center space-y-3"><h2 class="font-bold text-lg">Şəxsi mesajlar</h2><p class="text-sm" style="color:#9AA8B8">Mesajlaşmaq üçün real hesabınıza daxil olun.</p><button id="ngMessagesLogin" class="market-action market-primary">Daxil ol</button></div>`;
      $("ngMessagesLogin")?.addEventListener("click", () => openAuth("signin"));
      return;
    }
    host.innerHTML = `<div class="p-5 text-sm" style="color:#9AA8B8">Söhbətlər yüklənir...</div>`;
    try {
      const { data: memberships, error: mErr } = await client.from("conversation_members")
        .select("conversation_id,last_read_at").eq("user_id", currentUser.id);
      if (mErr) throw mErr;
      const ids = (memberships || []).map(x => x.conversation_id);
      let conversations = [], members = [], profiles = [];
      if (ids.length) {
        const [{ data: c, error: cErr }, { data: m, error: mmErr }] = await Promise.all([
          client.from("conversations").select("id,title,is_group,created_at").in("id", ids).order("updated_at", { ascending: false }),
          client.from("conversation_members").select("conversation_id,user_id").in("conversation_id", ids)
        ]);
        if (cErr) throw cErr;
        if (mmErr) throw mmErr;
        conversations = c || []; members = m || [];
        const userIds = [...new Set(members.map(x => x.user_id))];
        if (userIds.length) {
          const { data: p, error: pErr } = await client.from("profiles").select("id,username,display_name").in("id", userIds);
          if (pErr) throw pErr;
          profiles = p || [];
        }
      }
      const profileMap = new Map(profiles.map(p => [p.id, p]));
      const memberMap = new Map();
      members.forEach(m => {
        if (!memberMap.has(m.conversation_id)) memberMap.set(m.conversation_id, []);
        memberMap.get(m.conversation_id).push(m.user_id);
      });
      if (activeConversation && !ids.includes(activeConversation)) activeConversation = null;
      host.innerHTML = `
        <section class="p-3 space-y-3">
          <h2 class="font-bold text-lg" style="color:#19C7C7">Təhlükəsiz şəxsi mesajlar</h2>
          <form id="ngNewChat" class="flex gap-2">
            <input id="ngRecipient" class="modal-field min-w-0" placeholder="İstifadəçi adı (məs: ali_123)" maxlength="30" required>
            <button class="market-action market-primary whitespace-nowrap">Yeni söhbət</button>
          </form>
          <p id="ngChatError" class="text-[10px]" style="color:#ff8585"></p>
          <div class="grid gap-3">
            <div class="space-y-2">
              <h3 class="text-xs font-bold" style="color:#9AA8B8">SÖHBƏTLƏR</h3>
              ${conversations.length ? conversations.map(c => {
                const otherId = (memberMap.get(c.id) || []).find(id => id !== currentUser.id);
                const other = profileMap.get(otherId) || {};
                return `<button type="button" data-ng-conversation="${esc(c.id)}" class="w-full text-left rounded-xl border p-3" style="background:${activeConversation === c.id ? "#1A2230" : "#121820"};border-color:#2A364F">
                  <b class="text-xs">${esc(c.title || other.display_name || other.username || "Söhbət")}</b>
                  <span class="block text-[10px]" style="color:#9AA8B8">${c.is_group ? "Qrup" : "Şəxsi söhbət"} · ${esc(when(c.created_at))}</span>
                </button>`;
              }).join("") : `<p class="text-xs" style="color:#9AA8B8">Hələ söhbət yoxdur. İstifadəçi adı ilə yeni söhbət yaradın.</p>`}
            </div>
            <div id="ngChatPanel" class="rounded-2xl border p-3 space-y-3" style="background:#121820;border-color:#2A364F">
              ${activeConversation ? `<div id="ngMessagesList" class="space-y-2 max-h-[45vh] overflow-y-auto"><p class="text-xs" style="color:#9AA8B8">Mesajlar yüklənir...</p></div>
              <form id="ngSendMessage" class="flex gap-2"><input id="ngMessageBody" class="modal-field min-w-0" maxlength="10000" placeholder="Mesaj yazın..." required><button class="market-action market-primary">Göndər</button></form>` : `<p class="text-xs text-center" style="color:#9AA8B8">Mesajları açmaq üçün söhbət seçin.</p>`}
            </div>
          </div>
          <p class="text-[10px]" style="color:#9AA8B8">Mesajlar yalnız söhbət iştirakçılarına RLS siyasətləri ilə açıqdır. Bu versiya HTTPS və server icazələrindən istifadə edir; uçdan-uca şifrələmə (E2EE) iddia edilmir.</p>
        </section>`;
      host.querySelectorAll("[data-ng-conversation]").forEach(btn => btn.addEventListener("click", () => {
        activeConversation = btn.getAttribute("data-ng-conversation");
        renderMessages();
      }));
      $("ngNewChat")?.addEventListener("submit", createConversation);
      $("ngSendMessage")?.addEventListener("submit", sendMessage);
      if (activeConversation) await loadMessages(activeConversation);
    } catch (error) {
      host.innerHTML = `<div class="p-4 text-sm" style="color:#ff8585">Mesajlar yüklənmədi: ${esc(error.message)}</div>`;
    }
  }

  async function createConversation(event) {
    event.preventDefault();
    const box = $("ngChatError");
    const username = $("ngRecipient")?.value.trim().toLowerCase() || "";
    if (!/^[a-z0-9_]{3,30}$/.test(username)) { if (box) box.textContent = "Düzgün istifadəçi adı daxil edin."; return; }
    try {
      const { data: target, error: pErr } = await client.from("profiles")
        .select("id,username").eq("username", username).maybeSingle();
      if (pErr) throw pErr;
      if (!target) throw new Error("Bu istifadəçi adı ilə hesab tapılmadı.");
      if (target.id === currentUser.id) throw new Error("Özünüzlə söhbət başlada bilməzsiniz.");
      const { data: conversation, error: cErr } = await client.from("conversations")
        .insert({ created_by: currentUser.id, is_group: false }).select("id").single();
      if (cErr) throw cErr;
      const { error: mErr } = await client.from("conversation_members").insert([
        { conversation_id: conversation.id, user_id: currentUser.id },
        { conversation_id: conversation.id, user_id: target.id }
      ]);
      if (mErr) {
        await client.from("conversations").delete().eq("id", conversation.id);
        throw mErr;
      }
      activeConversation = conversation.id;
      await renderMessages();
    } catch (error) {
      if (box) box.textContent = error.message || "Söhbət yaradıla bilmədi.";
    }
  }

  async function loadMessages(conversationId) {
    const list = $("ngMessagesList");
    if (!list) return;
    try {
      const { data: messages, error } = await client.from("messages")
        .select("id,sender_id,kind,body,created_at,media_path")
        .eq("conversation_id", conversationId)
        .order("created_at", { ascending: true }).limit(100);
      if (error) throw error;
      const ids = [...new Set((messages || []).map(m => m.sender_id))];
      const { data: authors, error: aErr } = ids.length
        ? await client.from("profiles").select("id,display_name,username").in("id", ids)
        : { data: [], error: null };
      if (aErr) throw aErr;
      const map = new Map((authors || []).map(p => [p.id, p]));
      list.innerHTML = (messages || []).length ? messages.map(m => {
        const mine = m.sender_id === currentUser.id;
        const author = map.get(m.sender_id) || {};
        return `<div class="max-w-[88%] rounded-xl p-2 ${mine ? "ml-auto" : "mr-auto"}" style="background:${mine ? "rgba(25,199,199,.13)" : "#1A2230"}">
          <div class="text-[10px] mb-1" style="color:#19C7C7">${mine ? "Siz" : esc(author.display_name || author.username || "İstifadəçi")}</div>
          <p class="text-xs whitespace-pre-wrap break-words">${esc(m.body)}</p>
          <div class="text-[9px] text-right mt-1" style="color:#9AA8B8">${esc(when(m.created_at))}</div>
        </div>`;
      }).join("") : `<p class="text-xs text-center" style="color:#9AA8B8">Bu söhbətdə hələ mesaj yoxdur.</p>`;
      list.scrollTop = list.scrollHeight;
      if (messageChannel) await client.removeChannel(messageChannel);
      messageChannel = client.channel("ng-messages-" + conversationId)
        .on("postgres_changes", {
          event: "*", schema: "public", table: "messages",
          filter: "conversation_id=eq." + conversationId
        }, () => {
          if (activeConversation === conversationId) loadMessages(conversationId);
        }).subscribe();
    } catch (error) {
      list.innerHTML = `<p class="text-xs" style="color:#ff8585">${esc(error.message)}</p>`;
    }
  }

  async function sendMessage(event) {
    event.preventDefault();
    const input = $("ngMessageBody");
    const body = input?.value.trim() || "";
    if (!body || !activeConversation) return;
    const button = $("ngSendMessage")?.querySelector("button");
    if (button) button.disabled = true;
    try {
      const { error } = await client.from("messages").insert({
        conversation_id: activeConversation,
        sender_id: currentUser.id,
        kind: "text",
        body
      });
      if (error) throw error;
      if (input) input.value = "";
      await loadMessages(activeConversation);
    } catch (error) {
      const box = $("ngChatError");
      if (box) box.textContent = error.message || "Mesaj göndərilmədi.";
    } finally {
      if (button) button.disabled = false;
    }
  }

  async function init() {
    ensureStatus();
    if (!configured) { ready = true; showSetup(); return; }
    if (!sdk || typeof sdk.createClient !== "function") {
      ready = true;
      setStatus("Supabase JS kitabxanası yüklənmədi. İnternet/CDN bağlantısını yoxlayın.", "error");
      showLoading("Supabase SDK əlçatan deyil.");
      return;
    }
    try {
      client = sdk.createClient(cfg.url, cfg.publishableKey, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
      });
      window.NG_SUPABASE = client;
      const { data, error } = await client.auth.getSession();
      if (error) throw error;
      currentUser = data.session?.user || null;
      if (currentUser) await loadProfile();
      ready = true;
      setStatus(navigator.onLine ? "CANLI BAĞLANTI — real hesablar və server məlumatları aktivdir." : "OFLAYN — canlı server əməliyyatları hazırda mümkün deyil.", navigator.onLine ? "live" : "warn");
      client.auth.onAuthStateChange((event, session) => {
        currentUser = session?.user || null;
        if (!currentUser) { profile = null; activeConversation = null; }
        Promise.resolve().then(async () => {
          try { if (currentUser) await loadProfile(); } catch (e) { console.error(e); }
          renderCurrent();
          setStatus(currentUser ? "Hesab aktivdir — Supabase Auth." : "İctimai lent rejimi. Paylaşım və mesaj üçün daxil olun.", currentUser ? "live" : "info");
        });
      });
      feedChannel = client.channel("ng-public-feed")
        .on("postgres_changes", { event: "*", schema: "public", table: "posts" }, () => {
          if (activeTab === "feed") renderFeed();
        })
        .on("postgres_changes", { event: "*", schema: "public", table: "post_media" }, () => {
          if (activeTab === "feed") renderFeed();
        }).subscribe();
      renderCurrent();
    } catch (error) {
      ready = true;
      setStatus("Supabase bağlantı xətası: " + error.message, "error");
      showLoading("Backend bağlantısı qurulmadı. URL, public key və migration statusunu yoxlayın.");
    }
  }

  function renderUnavailableForTab(tab) {
    if (!configured || !client) { showSetup(); return; }
    if (!ready) { showLoading("Canlı bağlantı hazırlanır..."); return; }
    if (tab === "feed") renderFeed();
    else if (tab === "profile") renderProfile();
    else if (tab === "messages") renderMessages();
  }

  // Preserve the existing navigation engine; replace only the three live-social views.
  if (typeof window.openTab === "function") {
    const originalOpenTab = window.openTab;
    window.openTab = function (tabName) {
      activeTab = tabName;
      originalOpenTab.apply(this, arguments);
      if (["feed", "profile", "messages"].includes(tabName)) renderUnavailableForTab(tabName);
    };
  }

  window.NGSocial = {
    openAuth: () => openAuth("signin"),
    openComposer,
    refresh: renderCurrent,
    getClient: () => client
  };

  window.addEventListener("online", () => {
    if (configured && ready) setStatus("İnternet bərpa edildi. Canlı bağlantı yoxlanılır...", "info");
  });
  window.addEventListener("offline", () => {
    setStatus("OFLAYN — serverə yeni məlumat göndərilə bilməz.", "warn");
  });
  window.addEventListener("load", init, { once: true });
  ensureStatus();
})();
