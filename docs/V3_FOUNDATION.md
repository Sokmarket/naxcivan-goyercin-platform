# NAXÇIVAN GÖYƏRÇİN — V3 FOUNDATION

## Quraşdırma sərhədi

Bu paket mövcud `site/` tətbiqini yenidən yazmır. Yalnız yeni backend/migration və sənədləşdirmə faylları əlavə edir. `site/index.html`, `site/manifest.webmanifest` və `site/sw.js` dəyişdirilmir.

## Təklif edilən struktur

```text
repository/
├── .github/
│   └── workflows/
│       ├── pages.yml                 # Mövcud GitHub Pages workflow — qorunur
│       └── v3-foundation-checks.yml  # Yeni statik yoxlama
├── site/                             # Mövcud frontend — qorunur
│   ├── index.html
│   ├── manifest.webmanifest
│   └── sw.js
├── supabase/
│   ├── migrations/
│   │   └── 20261110000000_v3_foundation.sql
│   ├── functions/                    # Sonrakı mərhələlərdə Edge Functions
│   └── README.md
├── docs/
│   └── V3_FOUNDATION.md
└── .gitignore                        # Yalnız secret-ignore qaydaları əlavə olunur
```

## Bu mərhələnin cədvəlləri

- `profiles`, `user_roles`, `follows`
- `posts`, `post_media`, `comments`, `reactions`
- `pigeons`, `pigeon_media`, `lofts`, `breeding_pairs`
- `listings`, `listing_media`
- `conversations`, `conversation_members`, `messages`
- `reports`, `moderation_actions`, `notifications`

## Əsas təhlükəsizlik qərarları

1. `user_roles` üçün müştəri tərəfdən INSERT/UPDATE/DELETE icazəsi verilmir. Admin rolu yalnız Supabase SQL Editor kimi etibarlı idarəetmə kanalından təyin edilməlidir.
2. Göyərçinin təsdiq sahələrini adi istifadəçi dəyişə bilməz; moderator təsdiq qərarını verə bilər, lakin göyərçinin sahiblik və identifikasiya məlumatlarını dəyişə bilməz. Sahib halqa/identifikasiya məlumatını dəyişərsə əvvəlki təsdiq `pending` vəziyyətinə qaytarılır.
3. Satıcı özü elanını `active` və ya `removed` statusuna keçirə bilməz; moderator/admin statusu idarə edə bilər, moderator elan məzmununu və qiyməti dəyişə bilməz.
4. Mesajlar yalnız söhbət iştirakçılarına açıqdır.
5. `public-media` bucket yalnız ictimai paylaşımlar, profil şəkilləri, göyərçin və elan media faylları üçündür. Bucket adı ayrıca seçilir; obyekt açarı `<auth.uid()>/...` formatındadır. Şəxsi sənədlər və həssas baytarlıq qeydləri bu bucket-ə yüklənməməlidir.
6. Şəxsi yazışma əlavələri ayrıca, public olmayan `private-message-media` bucket-ində saxlanılır. Obyekt açarı `<conversation_uuid>/<auth.uid()>/<filename>` formatındadır; oxuma yalnız həmin söhbətin iştirakçılarına açıqdır.
7. SQL faylı demo istifadəçi, göyərçin, paylaşım və ya elan yaratmır.

## Vacib yoxlama qeydi

Bu ilkin miqrasiya mövcud Supabase verilənlər bazasının tam auditini əvəz etmir. Əgər Supabase layihəsində eyni adlı cədvəl, enum, trigger və ya policy artıq varsa, əvvəlcə remote schema `supabase db pull --remote` ilə versiya nəzarətinə alınmalı və miqrasiya uyğunlaşdırılmalıdır. Təmiz, yeni Supabase layihəsi üçün nəzərdə tutulub.

## Supabase açarları

- Brauzer tətbiqində yalnız publishable key istifadə edilə bilər və yalnız RLS siyasətləri düzgün olduqda.
- Secret key / köhnə `service_role` heç vaxt `site/`, `.env.example`, GitHub commit-i və ya brauzer JavaScript-ə yazılmamalıdır.
- Bu paket heç bir Supabase secret tələb etmir və heç bir açarı yaratmır.

## Tətbiq olunması

Ən təhlükəsiz ilk tətbiq:
1. Supabase-də yeni və ya ayrıca test layihəsi yaradın.
2. Dashboard → SQL Editor bölməsində migration faylının məzmununu nəzərdən keçirin.
3. SQL-i yalnız boş/test layihəsində tətbiq edin.
4. İki ayrı test hesabı ilə RLS sınaqları edin.
5. Daha sonra CLI ilə migration history idarəçiliyinə keçin.

CLI iş axını üçün rəsmi sənəd: https://supabase.com/docs/guides/local-development/database-migrations


## İlk admin hesabının təyin edilməsi

İlk test hesabı Supabase Auth vasitəsilə yaradıldıqdan sonra həmin hesabın UUID dəyərini Supabase Dashboard → Authentication → Users bölməsindən götürün. Yalnız etibarlı layihə sahibi SQL Editor-də aşağıdakı əmri öz UUID-si ilə icra etməlidir:

```sql
insert into public.user_roles (user_id, role)
values ('YOUR_AUTH_USER_UUID', 'admin')
on conflict (user_id, role) do nothing;
```

Bu əməliyyat adi brauzer istifadəçisinə açıq deyil. `user_roles` cədvəlində müştəri INSERT/UPDATE/DELETE siyasəti qəsdən yaradılmayıb. Admin rolunu istifadəçi profilindəki metadata-dan götürməyin.
