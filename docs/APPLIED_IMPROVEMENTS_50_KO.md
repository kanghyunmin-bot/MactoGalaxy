# 적용한 중요 개선 50개

## 클립보드 동기화

1. Mac 클립보드 폴링 주기를 0.4초에서 0.25초로 단축했다.
2. Mac 텍스트 클립보드 최대 크기를 256KB로 제한했다.
3. Mac 바이너리 클립보드 최대 크기를 24MB로 명시 제한했다.
4. Android 텍스트 클립보드 최대 크기를 256KB로 유지하고 검증을 강화했다.
5. Android 바이너리 클립보드 최대 크기를 24MB로 유지하고 base64 길이 사전 검증을 추가했다.
6. 클립보드 wire payload에 `protocolVersion`을 추가했다.
7. 클립보드 wire payload에 `sourceId`를 추가했다.
8. 클립보드 wire payload에 `itemId`를 추가했다.
9. 클립보드 wire payload에 `createdAtUnixMs`를 추가했다.
10. 클립보드 wire payload에 `sha256` 해시를 추가했다.
11. Mac 수신부에서 payload version을 검증한다.
12. Android 수신부에서 payload version을 검증한다.
13. Mac 수신부에서 바이너리 SHA-256을 검증한다.
14. Android 수신부에서 텍스트 SHA-256을 검증한다.
15. Android 수신부에서 바이너리 SHA-256을 검증한다.
16. Mac에서 자기 sourceId로 되돌아온 클립보드 echo를 무시한다.
17. Android에서 자기 sourceId로 되돌아온 클립보드 echo를 무시한다.
18. Mac URL 판별을 단순 prefix에서 `URLComponents` 기반으로 바꿨다.
19. Android URL 판별은 기존 구조를 유지하되 크기 검증 뒤에만 payload를 만든다.
20. Mac 이미지 수신 시 PNG 타입뿐 아니라 TIFF 표현도 같이 클립보드에 올린다.
21. Mac 이미지 수신 시 `NSImage` 객체도 pasteboard에 기록한다.
22. Mac 파일 클립보드는 일반 파일인지 확인한 뒤만 읽는다.
23. Mac 디렉터리/읽기 불가 파일은 전송하지 않는다.
24. Mac 파일명 sanitize를 `/` 치환에서 제어문자/예약문자 제거로 강화했다.
25. Android 파일명 sanitize를 제어문자/예약문자 제거로 강화했다.
26. Mac 파일명 길이를 96자로 제한했다.
27. Android 파일명 길이를 96자로 제한했다.
28. Android 바이너리 클립보드는 `ClipDescription`에 MIME 타입을 명시한다.

## 캐시와 히스토리

29. Mac 클립보드 캐시 최대 용량을 160MB로 제한했다.
30. Mac 클립보드 캐시 최대 파일 수를 80개로 제한했다.
31. Mac 클립보드 캐시 보존 기간을 7일로 제한했다.
32. Android 클립보드 캐시 최대 용량을 160MB로 제한했다.
33. Android 클립보드 캐시 최대 파일 수를 80개로 제한했다.
34. Android 클립보드 캐시 보존 기간을 7일로 제한했다.
35. Mac 히스토리 기본 demo 항목을 제거했다.
36. Android 히스토리 기본 demo 항목을 제거했다.
37. Mac 히스토리 최대 항목 수를 12개에서 50개로 늘렸다.
38. Android 히스토리 최대 항목 수를 24개에서 50개로 늘렸다.
39. Mac 히스토리 중복 제거를 추가했다.
40. Android 히스토리 title/detail 길이를 제한했다.
41. Mac 히스토리 크기 표시를 B/KB/MB human readable로 바꿨다.

## 프라이버시와 안정성

42. Mac UI의 Last inbound에서 클립보드 텍스트와 base64 데이터를 표시하지 않게 했다.
43. Mac UI의 Last inbound에서 public key와 hash도 표시하지 않게 했다.
44. Mac outbound frame 최대 크기를 제한했다.
45. Mac inbound receive buffer 최대 크기를 제한했다.
46. Android inbound frame 최대 크기를 제한했다.
47. Android outbound frame 최대 크기를 제한했다.
48. Android foreground notification에 클립보드 sync 활성 상태를 명확히 표시했다.

## Mirror/입력 충돌

49. `scrcpy` 실행 옵션에 `--no-clipboard-autosync`를 추가해 MtoG 클립보드 엔진과 충돌을 줄였다.
50. 우측 Command 단독 한/영 전환과 기존 `Command+Space`/`Control+Space` 경로를 문서화했다.

## 남은 구조적 과제

현재 50개는 MVP 코드 안에서 바로 반영 가능한 안정화다. 다음 구조 개선은 별도 작업이 필요하다.

- 24MB 초과 파일/영상은 base64 inline 대신 chunked transfer 또는 URI pull 방식으로 바꿔야 한다.
- ADB MVP 채널은 제품 보안 채널이 아니므로 앱 레벨 암호화 세션을 붙여야 한다.
- Android 앱별 rich clipboard는 앱이 URI 권한을 열어주는 범위 안에서만 가능하다.
