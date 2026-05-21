# Hướng dẫn thiết lập Firebase cho CChess

## 1. Mục tiêu

Tài liệu này hướng dẫn phần Firebase của Sprint 8:

- `8a`: cấu hình nền tảng Firebase
- `8b`: thiết kế dữ liệu và đồng bộ cloud

Sau khi hoàn tất, dự án cần đạt được:

- App Flutter kết nối được Firebase
- Có đăng nhập anonymous
- Có Firestore database
- Có schema tối thiểu cho user và dữ liệu hiện tại
- Có security rules đủ an toàn cho giai đoạn đầu
- Có đường đi rõ ràng để đồng bộ profile, quest, achievement và game history

## 2. Việc cần chốt trước khi bấm tạo project

### 2.1. Chốt tên định danh app thật

Hiện dự án vẫn đang dùng định danh mặc định:

- Android: `com.example.cchess`
- iOS: `com.example.cchess`

Trước khi đăng ký app vào Firebase, cần đổi sang tên bạn muốn dùng lâu dài, ví dụ:

- `vn.cchess.app`
- hoặc một tên khác bạn sở hữu

Lý do:

- Package ID / bundle ID là định danh quan trọng khi đăng ký Firebase app
- Đổi sau sẽ làm phát sinh thêm app config và tăng rối loạn cấu hình

### 2.2. Tạo môi trường riêng

Khuyến nghị có ít nhất:

- `cchess-dev`
- `cchess-prod`

Không dùng chung database dev và prod.

### 2.3. Chọn vùng Firestore

Người dùng chính của app dự kiến ở Việt Nam, vì vậy nên ưu tiên regional location gần người dùng, ví dụ Singapore.

Nguyên tắc:

- Chọn gần người dùng
- Chọn regional nếu muốn latency ghi thấp hơn và chi phí thấp hơn
- Chọn kỹ ngay từ đầu vì location database mặc định không đổi được sau khi provision

## 3. Dịch vụ Firebase nên bật trong Sprint 8

### Bắt buộc ở giai đoạn đầu

- Firebase Authentication
- Cloud Firestore

### Nên bật sớm nếu bạn đã xác định dùng

- Cloud Functions

### Chỉ bật khi có nhu cầu rõ

- Realtime Database: presence / online status
- Cloud Storage: avatar upload hoặc asset người dùng
- Cloud Messaging: push notification

## 4. Các bước thiết lập Firebase Console

### 4.1. Tạo project

Tạo:

- `cchess-dev`
- `cchess-prod`

Khuyến nghị:

- Bật Google Analytics nếu bạn muốn dùng analytics sớm
- Gắn billing account cho project cần Cloud Functions
- Tạo budget alert ngay sau khi bật billing

### 4.2. Tạo app trong Firebase project

Đăng ký theo platform bạn cần:

- Android
- iOS
- Web nếu thực sự cần

Khi thêm Android/iOS app:

- Dùng đúng package ID / bundle ID đã chốt
- Không đăng ký bằng `com.example.cchess` nếu đó chỉ là tên tạm

### 4.3. Bật Authentication

Giai đoạn đầu nên bật:

- Anonymous

Sau đó mới mở rộng:

- Google
- Apple
- Facebook

Lý do nên bắt đầu bằng Anonymous:

- Giúp app hoạt động ngay cả khi người dùng chưa muốn tạo tài khoản
- Dễ migrate lên social login sau này bằng account linking

### 4.4. Tạo Firestore database

Khuyến nghị:

- Bắt đầu với database ở `production mode`
- Tự viết rule của mình
- Không giữ `test mode` quá lâu

### 4.5. Cân nhắc Blaze plan

Nếu Sprint 8 có:

- Cloud Functions
- Backend server-side chính thức

thì nên chuẩn bị Blaze plan ngay, vì Functions cần gói có billing.

## 5. Cấu hình local cho Flutter project

### 5.1. Công cụ cần cài

- Firebase CLI
- FlutterFire CLI

### 5.2. Quy trình mong muốn

Từ thư mục `cchess/`:

1. Cài package Firebase cần dùng
2. Chạy `flutterfire configure`
3. Chọn project `dev` trước
4. Sinh file cấu hình theo platform
5. Khởi tạo Firebase trong `main.dart`

### 5.3. Package nên có ở Sprint 8

Trong giai đoạn đầu:

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`

Nếu bạn dùng thêm:

- `firebase_database`
- `cloud_functions`

### 5.4. Những file thường phát sinh

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

Lưu ý:

- Không nhầm file của `dev` và `prod`
- Không đưa service account JSON vào app client
- Với repo public, cần kiểm tra chính sách commit config file của nhóm

## 6. Schema Firestore tối thiểu cho CChess

### 6.1. Collection `users`

`users/{uid}`

Ví dụ field:

```json
{
  "displayName": "Kỳ Thủ",
  "region": "Hà Nội",
  "avatarUrl": null,
  "eloChess": 1000,
  "eloCup": 1000,
  "totalGames": 0,
  "wins": 0,
  "losses": 0,
  "draws": 0,
  "coins": 100,
  "gems": 10,
  "creditScore": 100,
  "isVip": false,
  "vipExpiresAt": null,
  "createdAt": "server timestamp",
  "lastActiveAt": "server timestamp",
  "onboardingCompleted": false
}
```

### 6.2. Subcollection `game_records`

`users/{uid}/game_records/{gameId}`

Lưu:

- opponent
- mode
- starting position
- move list
- result
- duration
- endedAt
- favorite flag

Lưu ý:

- Với ván local hoặc bot, client có thể tạo record trong giai đoạn đầu
- Với ván xếp hạng online, record chính thức nên do backend đáng tin cậy ghi sau khi server kết luận kết quả

### 6.3. Subcollection `achievements`

`users/{uid}/achievements/{achievementId}`

Lưu:

- `unlocked`
- `unlockedAt`

### 6.4. Subcollection hoặc document cho quest

Hai cách đều được:

1. `users/{uid}/daily_quests/{yyyy-mm-dd}`
2. `users/{uid}/daily_quest_state/current`

Tôi khuyên cách 1 nếu muốn giữ lịch sử theo ngày.

### 6.5. Dữ liệu global

Về sau có thể có:

- `puzzles/{puzzleId}`
- `openings/{openingId}`
- `leaderboards/chess/current/entries/{uid}`

## 7. Phân loại field client-writable và server-only

### Client có thể được phép sửa

- `displayName`
- `region`
- `avatarUrl`
- một số preference không nhạy cảm

### Chỉ server được phép sửa

- `eloChess`
- `eloCup`
- `coins`
- `gems`
- `creditScore`
- `isVip`
- `vipExpiresAt`
- `wins`
- `losses`
- `draws`
- `totalGames` nếu dùng ranked online chính thức

## 8. Security Rules giai đoạn đầu

### 8.1. Nguyên tắc

- User chỉ đọc/ghi hồ sơ của chính mình
- Client chỉ sửa được whitelist field
- Leaderboard public có thể đọc, nhưng client không ghi
- Giao dịch quan trọng phải do backend đáng tin cậy ghi

### 8.2. Rule khung tham khảo

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() {
      return request.auth != null;
    }

    function isOwner(uid) {
      return signedIn() && request.auth.uid == uid;
    }

    function onlyProfileEditableFieldsChanged() {
      return request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['displayName', 'region', 'avatarUrl', 'lastActiveAt', 'onboardingCompleted']);
    }

    match /users/{uid} {
      allow read: if isOwner(uid);
      allow create: if isOwner(uid);
      allow update: if isOwner(uid) && onlyProfileEditableFieldsChanged();
      allow delete: if false;

      match /game_records/{gameId} {
        allow read: if isOwner(uid);
        allow create: if isOwner(uid);
        allow update, delete: if isOwner(uid);
      }

      match /achievements/{achievementId} {
        allow read: if isOwner(uid);
        allow write: if false;
      }

      match /daily_quests/{dayId} {
        allow read: if isOwner(uid);
        allow write: if false;
      }
    }

    match /leaderboards/{document=**} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

### 8.3. Lưu ý

Rule trên chỉ là khung khởi đầu. Khi bạn cho phép quest / achievement chạy server-side, app client không nên tự ghi các bản đó nữa.

Khi bước sang ranked online, nên siết thêm:

- `game_records` chính thức của ranked match do backend ghi
- Client chỉ được sửa field cá nhân không nhạy cảm như `isFavorite`

## 9. Lộ trình sync từ code hiện tại lên cloud

### 9.1. Trạng thái hiện tại

Hiện dự án đang có local data:

- `UserProfile`
- `GameRecord`
- `DailyQuestState`
- `AchievementProgress`
- `PuzzleProgress`

### 9.2. Giai đoạn migrate

1. App khởi động
2. Firebase Auth trả `uid`
3. Đọc `users/{uid}`
4. Nếu chưa có:
   - tạo cloud profile từ local profile
5. Nếu đã có:
   - dùng cloud profile làm nguồn chính
   - đồng bộ xuống local cache

### 9.3. Điều cần tránh

- Không để local và cloud đều “có quyền quyết định cuối cùng”
- Không merge bừa các field nhạy cảm
- Không để client tự cộng coins / gems / ELO

## 10. Kế hoạch test nên có

### 10.1. Test thủ công

- Anonymous login
- Hoàn tất onboarding
- Đổi tên / khu vực
- Mở app lại vẫn thấy dữ liệu
- Đăng nhập trên máy khác vẫn thấy hồ sơ cloud

### 10.2. Test rules

- User A không đọc được `users/B`
- User A không sửa được `eloChess`
- User A chỉ sửa được field cho phép
- Client không ghi được leaderboard

### 10.3. Test khi offline

- App vẫn đọc local cache
- Khi có mạng lại thì sync hợp lý
- Không tạo hồ sơ trùng

## 11. Những thứ chưa nên đưa vào Sprint 8

- Full social graph
- Shop / inventory
- Notification phức tạp
- Video content
- OCR
- Tối ưu đa vùng
- Tự xây dashboard admin lớn

Sprint 8 nên dừng ở mức:

- Auth ổn
- Schema ổn
- Rule ổn
- Sync user ổn
- Có đường đi rõ cho backend realtime

## 12. Checklist hoàn thành Sprint 8a / 8b (✅ all done 2026-05-21)

- [x] Chốt package ID / bundle ID thật — `vn.cchess.app` đồng bộ 5 platforms.
- [x] Tạo project `cchess-dev`
- [x] Tạo project `cchess-prod`
- [x] Chọn Firestore region — `asia-southeast1` (Singapore).
- [x] Bật Anonymous Auth (cả dev + prod) + Google Sign-In.
- [x] Tạo Firestore database (production mode).
- [x] Cấu hình FlutterFire — `firebase_options.dart` + `google-services.json` + `GoogleService-Info.plist`.
- [x] App init Firebase được — `Firebase.initializeApp` trong [cchess/lib/main.dart](cchess/lib/main.dart).
- [x] Có `uid` — splash auto sign-in Anonymous; user có thể link Google qua Settings.
- [x] Tạo / đọc `users/{uid}` được — [cchess/lib/data/repositories/user_remote_repository.dart](cchess/lib/data/repositories/user_remote_repository.dart) + [cloud_sync_service.dart](cchess/lib/data/services/cloud_sync_service.dart).
- [x] Rule chặn field nhạy cảm — verified bằng test trong Cloud Test screen (3 case eloChess/coins deny + displayName allow).
- [x] Có document schema ghi lại trong repo — mục 6 doc này.
- [x] Đồng bộ được hồ sơ local hiện tại lên cloud — qua splash + `ProfileController._pushWhitelistChangesToCloud`.
- [ ] Có budget alert — **chưa set** vì hiện tại đã upgrade Blaze trên `cchess-dev` rồi (free tier headroom + đang dev), khuyến nghị setup khi gần production launch.

## 12.1. Gotcha thực tế khi deploy Cloud Functions lần đầu

Sau khi `firebase deploy --only functions` trên project vừa upgrade Blaze, có thể gặp:

```
Build failed: Access to bucket gcf-sources-<NUMBER>-<REGION> denied.
You must grant Storage Object Viewer permission to
<NUMBER>-compute@developer.gserviceaccount.com.
```

**Nguyên nhân**: Default Compute Engine service account của project mới không tự có quyền đọc bucket source code — đây là thay đổi IAM của Google từ T4/2024.

**Fix nhanh**: Vào https://console.cloud.google.com/iam-admin/iam → tìm principal `<NUMBER>-compute@developer.gserviceaccount.com` → thêm role `Editor` (hoặc tối thiểu `Storage Object Viewer` + `Artifact Registry Reader`). Đợi ~2 phút propagate rồi retry deploy.

Cũng gặp prompt:
> `No cleanup policy detected... How many days do you want to keep container images? (1)`

Chọn `1` (default) — chỉ giữ image của lần deploy gần nhất + 1 ngày trước, tiết kiệm chi phí Artifact Registry.

## 12.2. Region của triggers

- `recordRankedGame` (v2 callable) — region `asia-southeast1` qua `setGlobalOptions`.
- `createFirestoreUser` (v1 auth `onCreate` trigger) — region mặc định `us-east1`. **v1 Auth triggers không nghe `setGlobalOptions`**. Latency ~200ms cao hơn nhưng không nghiêm trọng vì chỉ chạy 1 lần đời account. Nếu muốn gần VN hơn, đổi sang v2 blocking trigger `beforeUserCreated` (API hơi khác).

## 13. Tài liệu liên quan trong repo

- `05_KE_HOACH_DU_AN.md`
- `06_KIEN_TRUC_BACKEND_THUC_DUNG.md`
- `08_HUONG_DAN_BACKEND_WEBSOCKET.md`

## 14. Tài liệu chính thức nên đọc thêm

- Add Firebase to your Flutter app
- Get Started with Firebase Authentication on Flutter
- Cloud Firestore Data model
- Get started with Cloud Firestore Security Rules
- Cloud Firestore locations
