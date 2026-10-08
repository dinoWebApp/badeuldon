---
name: badeuldon-git-deploy
description: 받을돈 Git 배포 스킬. 변경 사항을 커밋하고 원격 저장소에 Push 한다. "git 배포", "커밋", "푸시", "배포", "push", "커밋해줘", "푸시해줘" 요청 시 사용한다.
---

# 받을돈 Git 배포

## 이 스킬의 목적

변경 사항을 안전하게 커밋·푸시한다. 서버 배포(Kamal)는 별도 요청 시에만 다룬다 — 이 스킬의 기본 범위는 Git 커밋·Push다.

## 절차

1. **사전 점검**
   ```bash
   git status --short                  # 변경 범위 확인 — 의도하지 않은 파일 없는지
   git branch --show-current           # 브랜치 확인
   git ls-files --others --exclude-standard   # 미추적 파일 확인
   ```
2. **품질 게이트**: `bin/ci` 통과 확인 (RuboCop 0에러 + Brakeman 0경고 + 테스트 통과). 통과 못 하면 커밋 중단하고 사용자 보고.
3. **민감 파일 검사**: `config/master.key`, `config/credentials*.key`, `.env*` 가 스테이지에 없는지 확인. 있으면 즉시 중단.
4. **커밋**: 규약 메시지 형식 — 첫 줄 요약(한글 허용), 본문에 관련 Rule ID 명시. 예:
   ```
   청구서 무효 처리 기능 추가 (INV-6)

   - 무효 시 링크 폐기 + 시퀀스 중단
   - Rule ID: INV-4, INV-6, REM-7
   ```
5. **Push**: 현재 브랜치를 원격에 push. main/master 직접 push는 사용자 확인 후에만.
6. **완료 보고**: 커밋 해시·푸시 브랜치·포함 변경 요약.

## 안전 장치

- 충돌·리젝트 발생 시 `--force` 금지 — 원인 보고 후 사용자 판단 대기
- `.omp/progress.json`, `_workspace/`는 하네스 자산이므로 함께 커밋한다 (Git 추적이 규약)
- 작업 도중 다른 사람의 커밋이 원격에 있으면 pull --rebase 후 재검증
