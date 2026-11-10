# NAXÇIVAN GÖYƏRÇİN — Sosial Platforma və Bazar

Mobil öncelikli, tek sayfalı web arayüzü. GitHub Pages ile yayınlanacak statik site `site/` klasöründedir.

## İçerik
- Göyərçin topluluğu ve akış arayüzü
- Göyərçin, yem, kümes, taşıma ve bakım ürünleri için pazar arayüzü
- Yerel cihazda sepet, favori, ilan ve sipariş talebi kayıtları
- Baytarlık hizmeti ve klinik kayıt başvuru arayüzleri
- PWA manifesti ve Service Worker
- Termux üzerinden tek komutla GitHub deposu oluşturma ve Pages yayınlama

## Termux'ta yayınlama
1. Bu ZIP dosyasını Android'in `Download` klasörüne indir.
2. Termux'ta aşağıdaki tek blok komutu çalıştır:
   ```bash
   pkg update -y && pkg install -y git gh unzip && termux-setup-storage && mkdir -p "$HOME/ng-publish" && unzip -o "$HOME/storage/downloads/Naxcivan_Goyercin_GitHub_Termux.zip" -d "$HOME/ng-publish" && cd "$HOME/ng-publish/Naxcivan_Goyercin_GitHub_Paket" && bash ./publish_termux.sh
   ```
3. İlk kullanımda GitHub CLI web/device login ister; ekranda gösterilen kodu GitHub'da onayla.
4. Script yeni bir **public** repo oluşturur, dosyaları `main` dalına gönderir, GitHub Pages'i GitHub Actions ile yapılandırır ve yayınlama iş akışını bekler.

## Önemli işlev sınırları
Bu sürüm statik web sitesidir. İlan, sepet, favori, sipariş ve veteriner başvuru kayıtları kullanıcının o tarayıcı/cihazında tutulur. Gerçek çok kullanıcılı hesaplar, sunucu tarafı ilanlar, çevrimiçi ödeme, kargo entegrasyonu, gerçek zamanlı mesajlaşma ve veteriner lisans doğrulaması için ayrıca backend, veritabanı, kimlik doğrulama ve yönetim paneli gerekir.

Reçeteli veteriner ilaçları, antibiyotikler ve aşılar serbest ilan olarak açılmamıştır; ilgili mevzuat, yetkili satıcı ve veteriner kontrolü gerekir.

## Güvenlik
Repo sahibi, GitHub hesabı üzerinden repo yöneticisi (admin) olur. Script herkese admin yetkisi vermez. GitHub CLI yalnızca `repo` ve `workflow` kapsamlarını talep eder; ilgisiz hesap/organizasyon yetkileri istenmez. Pages iş akışı da sadece `contents: read`, `pages: write`, `id-token: write` izinlerini kullanır.
