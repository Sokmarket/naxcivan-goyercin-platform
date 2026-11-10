# V3 Foundation — RLS qəbul sınaqları

Bu siyahı test Supabase layihəsində iki ayrı Auth hesabı (A və B) ilə yoxlanmalıdır. Production məlumatları ilə sınaq aparmayın.

## Hesablar və profillər
- [ ] A və B ayrı hesablar kimi qeydiyyatdan keçir.
- [ ] Hər hesab üçün `profiles` sətri avtomatik yaradılır.
- [ ] A öz profilini dəyişə bilir, B-nin profil sətrini dəyişə bilmir.
- [ ] A özünə `admin` və ya `moderator` rolu əlavə edə bilmir.

## Sosial paylaşım
- [ ] A-nın `public` paylaşımını B və anonim ziyarətçi oxuya bilir.
- [ ] A-nın `private` paylaşımını yalnız A oxuya bilir.
- [ ] A-nın `followers` paylaşımını B yalnız A-nı izlədikdən sonra oxuya bilir.
- [ ] B A-nın paylaşımını A-nın adından dəyişə və ya silə bilmir.
- [ ] B yalnız öz adından şərh və reaksiya yarada bilir.

## Göyərçin reyestri
- [ ] A ictimai göyərçin qeydini B-yə görünən yaradır.
- [ ] A şəxsi göyərçin qeydini B-dən gizli saxlayır.
- [ ] A `verification_status`, `verified_at` və `verified_by` sahələrini dəyişə bilmir.
- [ ] Moderator təsdiq statusunu idarə edə bilir, lakin göyərçin sahibini və identifikasiya sahələrini dəyişə bilmir.
- [ ] Sahib halqa/identifikasiya məlumatını dəyişəndə əvvəlki təsdiq `pending` olur.
- [ ] Halqa identifikatoru (ölkə + verən təşkilat + nömrə) təkrarlana bilmir.

## Bazar
- [ ] Yeni elan `draft` statusu ilə başlayır və ictimai istifadəçiyə görünmür.
- [ ] `pending_review` elan da ictimai siyahıda görünmür.
- [ ] Satıcı öz elanını birbaşa `active` edə bilmir.
- [ ] Yalnız moderator/admin elan statusunu `active` edə bilir.
- [ ] Moderator elan başlığını, mətnini, qiymətini və satıcısını dəyişə bilmir.
- [ ] Aktiv elan başqa istifadəçiyə görünür.

## Mesajlaşma
- [ ] A söhbət yaradır və B-ni iştirakçı kimi əlavə edir.
- [ ] A və B mesajları oxuya bilir.
- [ ] C adlı üçüncü hesab söhbətin mesajlarını oxuya bilmir.
- [ ] İştirakçı yalnız öz `last_read_at` sahəsini yeniləyə bilir.
- [ ] Adi istifadəçi `system` tipli mesaj yarada bilmir.
- [ ] İştirakçı olmayan hesab söhbətə özünü əlavə edə bilmir.

## Storage
- [ ] A yalnız `public-media/<A_USER_UUID>/...` qovluğuna yükləyə bilir.
- [ ] A, B-nin qovluğuna fayl yükləyə və ya onu silə bilmir.
- [ ] İstifadəçi başqa sahibin storage fayl yolunu öz postuna/göyərçininə/elanına bağlaya bilmir.
- [ ] Şəxsi sənədlər `public-media` bucket-inə yüklənmir.

## Qəbul meyarı
Bütün sınaqlar keçmədən real istifadəçi məlumatlarını bu backend-ə köçürməyin. Sınaq nəticələrini və Supabase migration tarixçəsini saxlayın.
