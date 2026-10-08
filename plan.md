# 범용 개발 워크스페이스 계획

**기반:** Debian 13 slim · s6-overlay · Podman-in-Podman  
**사용자:** 호스트 rootless 사용자 `1000:1000` · 컨테이너 개발 계정 `admin:1000:1000`  
**문서 상태:** 구현 방향과 완료 기준을 정한 설계안. 실제 호스트에서의 통합 검증 완료를 뜻하지 않는다.  
**기술 문서 확인일:** 2026-10-08

## 1. 목적과 철학

이 환경은 **zsh에 들어가 직접 설치하고 수정하며 사용하는 범용 개발용 Linux 컨테이너**다. 특정 프로젝트, 애플리케이션, AI 에이전트의 실행 이미지가 아니다. 사람과 자동화 도구가 같은 개발 환경을 사용할 수 있어야 한다.

호스트에는 컨테이너 실행에 필요한 기반만 둔다. 프로젝트 때문에 필요한 컴파일러, 헤더, `-dev`/`-devel` 패키지, SDK와 각종 빌드 도구는 워크스페이스 안에 설치한다. “호스트를 깨끗하게 유지한다”는 것은 **호스트의 패키지·설정과 프로젝트 의존성을 분리한다**는 뜻이지, 컨테이너 데이터가 호스트 디스크를 사용하지 않는다는 뜻은 아니다.

`ubuntu-slim-zsh`의 **작은 기반 이미지, zsh 중심의 사용 경험, 필요할 때 선택적으로 초기화·확장하는 방식**을 따른다. 기존 저장소의 `dumb-init → zsh` 구조에서 init 부분을 s6-overlay로 바꾸고, 사용자의 작업 방식은 유지한다. Ubuntu용 설치 스크립트를 Debian에 검토 없이 복사하지 않는다.[1]

**Podman-in-Podman과 s6는 워크스페이스의 목적이 아니라, 개발 중 막히지 않도록 미리 준비하는 기반 기능이다.**

## 2. 설계 원칙

| 원칙 | 결정 |
|---|---|
| 셸 우선 | 기본 진입점의 사용자 경험은 `admin`의 대화형 zsh다. API 서버나 대시보드를 먼저 사용하게 하지 않는다. |
| 수정 가능한 환경 | 실행 중 패키지 설치, 설정 변경, 서비스 추가를 정상적인 사용 방식으로 인정한다. 매번 이미지 재빌드를 요구하지 않는다. |
| 작은 초기 이미지 | init·셸·sudo·PiP 기반을 포함한다. 모든 언어 도구와 개발 서비스를 선설치하지 않는다. |
| 내부 관리 권한 | s6는 root로, 개발 작업은 admin으로 실행한다. admin에게 passwordless sudo ALL을 제공한다. |
| 데이터 보존 | 재접속이나 시작 과정에서 컨테이너 교체, home 덮어쓰기, 이미지·캐시 정리를 자동으로 하지 않는다. |
| 정확한 테스트 | 서비스가 실제로 실행되고 응답하는지 검사한다. 오류 메시지를 숨기거나 성공 코드를 위조하지 않는다. |

경량화는 “패키지를 설치할 수 없는 환경”을 만드는 일이 아니다. **기본 이미지만 작게 유지하고, 사용자가 필요에 따라 키울 수 있게 만드는 것**이다.

## 3. 전체 구조

```text
Host: 일반 사용자 1000:1000
└── rootless Podman
    └── Workspace: Debian 13 slim
        │
        ├── /init → s6 감독 트리                       root
        │   ├── runtime·권한 초기화
        │   ├── 사용자가 등록한 서비스
        │   └── Podman API                            admin, 선택 실행
        │
        ├── 기본 대화형 zsh                           admin
        │   ├── sudo → 패키지·시스템 설정 관리
        │   ├── 프로젝트 빌드·테스트·디버깅
        │   ├── GUI·오디오 프로그램
        │   └── 로컬 Podman CLI
        │
        └── 내부 Podman / conmon / crun
            └── 필요할 때 생성하는 작업·테스트 컨테이너
```

워크스페이스 자체를 **바깥 컨테이너**, 그 안의 Podman이 생성하는 것을 **안쪽 컨테이너**라고 부른다. 호스트 systemd의 사용 여부는 바꾸지 않는다. 없애려는 의존성은 워크스페이스 내부에서 systemd가 실행 중이라고 가정하는 경로다.

## 4. 사용 경험과 컨테이너 수명

### 기본 모드: 실행하면 zsh

이미지의 init은 `/init`으로 고정하고, 기본 `CMD`가 admin으로 전환한 뒤 zsh를 실행하도록 한다. 아래는 **구현할 인터페이스의 목표**이며, `as-admin`은 프로젝트에서 제공할 사용자 전환 helper다.

```dockerfile
USER root
ENTRYPOINT ["/init"]
CMD ["/usr/local/bin/as-admin", "/usr/bin/zsh", "-l"]
```

호스트 launcher는 TTY와 표준 입력을 연결한다. `--entrypoint`로 zsh나 tmux를 직접 지정해 s6를 우회하는 방식은 사용하지 않는다.

기본 대화형 모드에서는 zsh가 종료되면 s6가 서비스를 정리하고 컨테이너를 정지한다. **정지는 삭제가 아니다.** 기본 실행에 `--rm`을 사용하지 않으며, 다음 작업에서는 같은 컨테이너를 다시 시작한다. s6-overlay는 CMD로 대화형 프로그램을 실행하고, 해당 프로그램 종료 시 컨테이너를 정리하는 방식을 지원한다.[2]

### 선택 모드: tmux·장기 실행

tmux는 선택 도구로 제공하되 강제 진입점으로 삼지 않는다. 터미널과 독립적인 수명이 필요할 때만 명시적인 장기 실행 모드와 별도 셸 접속을 사용한다.

tmux detach로 주 CMD가 종료되면 컨테이너도 종료될 수 있으므로, “tmux를 사용한다”와 “컨테이너가 계속 실행된다”를 같은 의미로 구현하지 않는다.

### 대표 사용 시나리오

사용자가 호스트의 작업 폴더를 연결해 zsh에 들어온다. C/C++ 프로젝트에 필요한 `build-essential`, `cmake`, `libssl-dev`를 컨테이너 안에서 sudo로 설치하고 빌드한다. 테스트에 필요한 서버는 foreground 또는 s6 서비스로 실행하고, 별도 Linux 환경이 필요하면 안쪽 Podman으로 컨테이너를 만든다. 작업을 마친 뒤 정지했다가 다시 시작하면 설치한 도구와 설정을 그대로 사용한다. **이 과정에서 프로젝트용 개발 패키지를 호스트에 설치하지 않는다.**

## 5. 이미지 구성과 권한

### 초기 이미지에 포함할 범위

| 영역 | 포함할 구성 |
|---|---|
| 운영체제 | `debian:13-slim`, 인증서, locale·timezone, 기본 진단 도구 |
| 셸 | zsh, sudo, tmux, 최소 셸 설정 |
| init | s6-overlay와 기본 초기화·종료 처리 |
| 중첩 실행 | Podman, crun, conmon, uidmap, fuse-overlayfs, 필요한 네트워크 helper |
| 운영 보조 | 사용자 전환, 환경 확인, 서비스 관리에 필요한 작은 스크립트 |

이미지와 s6-overlay 버전·checksum을 관리하고 빌드 결과에 실제 패키지 버전을 기록한다. 호스트에 컴파일러를 설치해서 빌드하는 절차는 두지 않는다.

언어별 SDK, C/C++ 빌드 도구, 데이터베이스, GUI toolkit, Oh My Zsh 등의 확장은 **컨테이너 내부에서 직접 설치하거나 선택형 bootstrap으로 설치**한다. 부팅·셸 접속 때마다 패키지를 설치하거나 원격 설치기를 자동 실행하지 않는다.

`DEBIAN_FRONTEND=noninteractive` 같은 빌드 편의 설정은 빌드 범위로 제한한다. 대화형 개발 환경에서 사용자가 패키지 설정 질문에 응답하는 기능까지 불필요하게 없애지 않는다.

### root와 admin

s6와 초기화는 컨테이너 root로 실행한다. admin의 로그인 셸은 zsh이며, sudo 정책은 다음과 같다.[3]

```sudoers
admin ALL=(ALL:ALL) NOPASSWD: ALL
```

호스트 사용자와 admin의 파일 소유권을 맞추는 `keep-id` 매핑을 유지하되, init을 root로 시작하도록 바깥 실행에서 `--user=0:0`을 명시한다. `keep-id`는 명시적인 사용자 지정이 없으면 이미지의 `USER`보다 우선할 수 있다.[4]

호스트의 장치 접근용 보조 그룹은 crun의 `keep-groups`로 전달하고, root에서 admin으로 전환하는 helper도 이 그룹을 보존한다. sudo의 그룹 정책까지 포함해 실제 장치 접근으로 검증한다.[4][5]

기본 개발 프로필은 넓은 capability와 필요한 보안 필터 완화를 허용하는 방향으로 구현한다. `cap-add=ALL`, label/seccomp/AppArmor 완화, 마스킹 완화를 검증 출발점으로 삼되 적용 가능 여부와 실제 설정을 명시한다. 모든 장치를 무차별 노출하는 `--privileged`는 기본으로 삼지 않는다.

이 환경은 신뢰하는 개발 코드용이다. **sudo와 capability를 넓혀도 rootless 호스트 사용자에게 없는 권한은 생기지 않는다.** uidmap helper와 sudo를 막는 `no-new-privileges` 또는 실행 경로의 `nosuid` 조건도 검사 대상이다.[4][5]

## 6. Podman-in-Podman: 생성 전에 준비할 기반

Podman 패키지 자체는 나중에 설치할 수 있다. 까다로운 부분은 **바깥 컨테이너를 생성할 때 정해지는 장치, 보안 설정, namespace 및 저장소 조건**이다. 따라서 launcher와 이미지가 이를 함께 준비해야 한다.

| 생성 전에 준비할 것 | 구현 기준 |
|---|---|
| 중첩 user namespace | 호스트의 실제 subordinate UID/GID와 바깥 매핑 범위를 확인하고 안쪽 위임 범위를 산정한다. |
| uidmap helper | admin이 필요한 매핑을 만들 수 있도록 helper·권한·마운트 옵션을 검증한다. |
| 스토리지 | fuse-overlayfs를 기본 호환 경로로 준비하고 `/dev/fuse`를 전달한다. |
| graphroot | 바깥 writable layer와 분리한 전용 영속 저장소에 둔다. |
| 네트워크 | systemd 없이 동작하는 rootless 네트워크 경로를 준비한다. |
| cgroup·로그 | 내부 Podman이 systemd manager나 journald에 의존하지 않도록 설정한다. |

안쪽 `/etc/subuid`와 `/etc/subgid`에 임의의 큰 범위를 적는 것으로 해결하지 않는다. **그 ID들이 바깥 user namespace에도 실제로 매핑되어 있어야 한다.** 최초 구현은 호스트에 흔히 제공되는 65,536개 subordinate ID 범위를 우선 검증하고, 매핑은 저장소와 함께 고정한다. 범위를 바꾸면서 기존 저장소를 조용히 재사용하지 않는다.[4]

### 내부 엔진의 기본 정책

기본 엔진은 admin의 rootless Podman이다. admin의 CLI와 API가 같은 설정·저장소를 사용한다. 사용자 설정은 가능한 한 Podman의 표준 경로를 사용하고, 전역 환경변수로 사용자 설정을 무조건 무시하게 만들지 않는다.[6]

admin의 graphroot는 `/home/admin/.local/share/containers/storage`, runroot는 `/run/user/1000` 아래에 둔다. root의 Podman 저장소는 별도로 유지한다. **`sudo podman`은 admin 엔진에 권한을 추가하는 명령이 아니라 다른 사용자 엔진을 사용하는 동작**으로 문서화한다.[7]

초기 호환 기준은 내부 cgroup 생성 비활성화, `cgroupfs` manager 선택, 파일 기반 로그·이벤트다. 이는 systemd 없는 기본 실행을 단순화하기 위한 결정이며, 안쪽 컨테이너별 CPU·메모리 제한까지 지원한다는 뜻은 아니다.[6]

네트워크는 바깥 컨테이너를 rootless 방식으로 분리하고, 안쪽 기본값은 바깥 컨테이너의 네트워크를 공유하는 경량 경로로 시작한다. 별도 네트워크·포트 매핑이 필요한 테스트는 독립 프로필로 검증한다. 안쪽의 host networking에서 “host”는 바깥 컨테이너이며 물리 호스트가 아니다.[4]

### API는 선택 기능

로컬 Podman CLI를 기본으로 사용한다. Docker API 호환 도구 등이 필요할 때 s6에서 admin의 API 서비스를 실행한다. 소켓은 `/run/user/1000/podman/podman.sock`이며 TCP로 공개하지 않는다. systemd socket activation 대신 프로세스를 직접 실행할 수 있다.[8]

호스트 Podman 소켓을 마운트하는 방식으로 PiP를 대체하지 않는다. API가 고장 나더라도 이를 진단할 zsh는 사용할 수 있어야 하며, API 재시작만으로 안쪽 컨테이너를 전부 종료하지 않는다.

## 7. s6와 자동화 도구의 서비스 실행

### 해결할 문제와 해결하지 않는 문제

s6의 역할은 서비스 프로세스 실행·감독, 의존 순서, 종료 처리와 상태 확인이다. **s6를 설치한다고 `systemctl` 명령이나 systemd API가 호환되는 것은 아니다.** s6/s6-rc는 별도 인터페이스를 제공한다.[2][9]

| 상황 | 처리 원칙 |
|---|---|
| init 없이 데몬을 유지·재시작해야 함 | s6 longrun으로 foreground 프로세스를 감독한다. |
| Unix socket을 사용하는 서버 | 프로그램이 소켓을 생성하도록 실행하고 실제 응답을 검사한다. |
| systemd manager·journald를 기본으로 쓰는 내부 Podman | systemd 없는 설정으로 바꾼다. |
| 설치기가 서비스를 자동 시작하려 함 | Debian의 서비스 시작 정책과 필요한 패키지별 처리를 적용한다. |
| 스크립트가 `systemctl`을 직접 호출함 | 스크립트·서비스 실행 방식을 바꾸거나 명시적인 제한 어댑터가 필요하다. 자동 해결로 취급하지 않는다. |
| 테스트 대상이 systemd 자체에 의존함 | 별도 systemd 테스트 환경이 필요하다. 이 기본 워크스페이스의 보장 범위 밖이다. |

`systemctl`을 항상 성공하는 스크립트로 바꾸거나, `|| true`로 서비스 실패를 감추는 방식은 사용하지 않는다. AI 에이전트에게 필요한 것은 오류가 안 보이는 환경이 아니라 **성공과 실패를 정확히 판별할 수 있는 실행 환경**이다.

### 개발 중 서비스 추가·변경

기본 기반 서비스는 s6-rc로 관리한다. 사용자가 나중에 설치한 서비스도 바깥 컨테이너 재생성 없이 등록·변경할 수 있어야 한다.

이를 위한 작은 관리 helper를 구현 대상으로 둔다. 기능은 등록·적용, 시작·중지·재시작, 상태·로그·준비 확인으로 제한한다. systemd 전체를 흉내 내는 계층은 만들지 않는다.

서비스 정의 변경은 새로운 데이터베이스를 컴파일한 뒤 `s6-rc-update`로 반영하는 경로를 검증한다. 실행 중인 compiled database를 직접 덮어쓰지 않고, s6-overlay의 기반 서비스를 보존한다. 이 도구는 부분 전환 실패도 보고하므로 “실패하면 자동으로 원복된다”고 가정하지 않는다. 재시작 뒤에도 같은 정의를 적용하는지 검사한다.[10]

서비스별 실행 사용자, 작업 디렉터리, 환경, foreground 명령, 종료 신호, readiness를 명시한다. 시스템 서비스가 사용자의 대화형 `.zshrc`를 읽어야만 실행되는 구조는 피한다.

### 패키지 설치와 테스트의 구분

Debian의 `policy-rc.d`는 지원되는 설치 경로에서 서비스 자동 시작을 제어하는 수단으로 사용한다. 이는 systemd 호환층도 아니고, 서비스를 실행했다는 증명도 아니다. 정책을 우회해 systemctl을 직접 부르는 설치기는 별도 처리 대상이다.[11]

자동화용 환경 설명에는 “PID 1은 s6”, “일반 명령은 admin, 시스템 변경은 sudo”, “서비스는 foreground 또는 등록된 s6 인터페이스로 관리”, “로그와 실제 health check로 검증”을 명시한다.

**프로세스 존재와 준비 완료는 구분한다.** 등록한 상태와 실제 응답 결과가 다르면 테스트가 실패해야 한다. 서비스가 아닌 일반 빌드·테스트 프로세스는 zsh나 테스트 runner에서 그대로 실행할 수 있어야 한다.[9]

## 8. Wayland·오디오·장치

표준적인 사용자 runtime 구조를 유지한다.

```text
/home/admin/
/home/admin/workspace/                    선택한 호스트 작업 폴더

/run/user/1000/                           admin 소유, mode 0700
├── wayland-0                            필요한 호스트 소켓만 연결
├── pulse/native                         필요한 호스트 소켓만 연결
├── pipewire-0                           필요한 호스트 소켓만 연결
├── podman/podman.sock                    내부 API가 생성
└── containers/                          내부 Podman의 일시적 상태
```

`XDG_RUNTIME_DIR=/run/user/1000`을 설정하고, `WAYLAND_DISPLAY`에는 `wayland-0` 같은 실제 display 이름을 사용한다. 호스트에서 `wayland-1`을 쓰면 그 값을 반영한다. 상대 display 이름은 XDG runtime 디렉터리 기준으로 해석된다.[12][13]

호스트 runtime 디렉터리 전체를 공유하지 않는다. 그래픽·오디오 소켓만 연결하고 내부 Podman runtime과 분리한다. 소켓 bind mount의 read-only 속성을 프로토콜의 읽기 전용 권한으로 오해하지 않는다.

`/dev/dri`, `/dev/accel`, `/dev/snd`, `/dev/net/tun`은 호스트에 있고 실제 사용할 때 전달한다. headless 호스트에서 선택 장치·소켓이 없다는 이유만으로 zsh를 사용할 수 없게 하지 않는다. 단, 선택한 PiP storage 경로에 필요한 `/dev/fuse`의 부재는 PiP 사용 불가로 명확히 보고한다.

호스트 장치 권한, 보조 그룹 유지, 컨테이너 안의 사용자 공간 라이브러리를 함께 검사한다. 소켓·장치 전달만으로 GUI나 GPU 동작이 완성되었다고 판정하지 않는다.

공유 TUN/VPN은 바깥 컨테이너에서 관리하는 경로를 우선한다. 바깥에 전달한 장치가 안쪽에 자동 전달되지는 않는다. 안쪽 GUI·GPU·TUN 테스트에는 별도의 장치·소켓·namespace 설정이 필요하다.

## 9. 상태 보존과 재생성 정책

기본 단위는 오래 사용하는 개발 컨테이너다. 명시적인 삭제·재생성 전까지 writable layer를 보존한다.

| 상태 | 위치 | 같은 컨테이너 정지·시작 | 컨테이너 삭제·재생성 |
|---|---|---|---|
| 시스템 패키지, `/etc` 설정 | 바깥 writable layer | 유지 | 별도 기록·백업 없으면 소실 |
| admin home·사용자 SDK·캐시 | 전용 영속 저장소 | 유지 | 다시 연결하면 유지 |
| 프로젝트 소스 | 선택한 호스트 폴더 | 유지 | 유지 |
| 내부 이미지·컨테이너·볼륨 | 전용 graphroot 저장소 | 유지 | 호환 설정으로 재연결 필요 |
| runtime·소켓·실행 상태 | `/run` 등 임시 영역 | 다시 생성 | 다시 생성 |

시스템 패키지 설치를 매번 Containerfile에 옮기도록 강요하지 않는다. 다만 환경을 다른 곳에서 재현하거나 기본 이미지를 교체할 때는 설치 목록·설정·명시적 bootstrap으로 정리한다. **home만 보존한다고 APT 설치 상태까지 보존되는 것은 아니다.**

호스트 작업 폴더를 재귀적으로 chown/chmod하거나, 기본 동작으로 Podman prune/reset을 실행하지 않는다. 저장소와 컨테이너 이름은 사용자 지정값이며 프로젝트의 정체성으로 취급하지 않는다.

정상 종료에서는 사용자 서비스와 안쪽 컨테이너를 정리하고 내부 mount를 해제한다. 저장된 안쪽 컨테이너를 다음 부팅에 전부 자동 시작하지는 않는다. 자동 시작은 사용자가 지정한 대상에만 적용한다.

## 10. 구현 순서와 완료 기준

### 구현 단계

| 단계 | 작업 | 다음 단계로 넘어갈 조건 |
|---|---|---|
| 1. 셸 기반 | Debian slim, zsh, root s6, admin·sudo, 기본 실행·재접속 | 실제 TTY와 비대화형 실행 모두 성공 |
| 2. 상태·권한 | UID/GID, 보조 그룹, home·workspace·runtime 분리 | 파일 소유권과 sudo, 정지·시작 후 보존 확인 |
| 3. PiP | uidmap, FUSE, 저장소·네트워크·cgroup 설정 | 실제 안쪽 이미지 pull·build·run·stop 성공 |
| 4. 서비스 관리 | 기본 s6 서비스, 실행 중 정의 반영, 선택 API, 환경 설명 | systemd 없이 실제 응답·재시작·실패 판별 성공 |
| 5. 데스크톱·장치 | Wayland·오디오·GPU·TUN 선택 전달 | 대상 장치에서 기능별 통합 검사 통과 |

산출물은 `Containerfile`, 최소 `rootfs/`, 셸 설정, 선택형 `init.d/`, 생성·접속·검증 helper로 제한한다. wrapper가 일반 Podman·zsh·APT 사용을 가로막는 자체 플랫폼으로 커지지 않게 한다.

### 필수 검증

| 항목 | 통과 기준 |
|---|---|
| 호스트 오염 방지 | 생성·접속·개발 과정에서 프로젝트용 개발 패키지를 호스트에 설치하지 않는다. |
| 기본 UX | 초기화 후 admin zsh에 도달하며, 프롬프트·신호·종료 동작이 정상이다. |
| 비대화형 자동화 | TTY 없이 명령을 실행할 수 있고, 종료 코드와 stdout/stderr가 보존된다. |
| 내부 관리 권한 | 무암호 sudo로 실제 패키지 설치와 시스템 설정 변경을 수행한다. |
| UID/GID·보조 그룹 | workspace 파일이 호스트 사용자 소유이며, 필요한 장치에 실제 접근한다. |
| 변경 상태 유지 | 같은 컨테이너 재시작 후 설치한 패키지·설정·사용자 데이터가 유지된다. |
| PiP | 실제 중첩 build와 run, 여러 파일 UID/GID, DNS·외부 연결을 검사한다. |
| 서비스 | 생성 이후 추가한 서비스가 실행·재시작되고, 잘못된 설정과 응답 실패를 구별한다. |
| 선택 API | API 미사용 시 CLI가 동작하고, 활성화 시 실제 socket 요청이 성공한다. |
| 종료·재시작 | 정리 과정이 완료되고, 다음 시작에 저장소·mount·runtime이 정상 복구된다. |

GUI·오디오·GPU·TUN은 별도 기능별 검사로 기록한다. 장치가 없어 검사하지 못한 항목을 “통과”로 처리하지 않는다. 정적 문법 검사, UID 범위 계산, 실제 PiP 부팅, 실제 장치 동작은 서로 다른 검증 단계로 보고한다.

---

## 근거 문서

아래 자료는 기술적 동작의 근거다. 위 기본값·우선순위·인터페이스는 이 워크스페이스의 설계 결정이며 upstream의 기본 동작이나 이미 완료된 구현으로 해석하지 않는다.

| 번호 | 자료 |
|---|---|
| 1 | [ubuntu-slim-zsh — README·Dockerfile][1] |
| 2 | [s6-overlay — init·CMD·서비스·종료][2] |
| 3 | [Debian 13 — sudoers][3] |
| 4 | [Podman — run][4] |
| 5 | [Debian 13 — setpriv][5] |
| 6 | [Debian 13 — containers.conf][6] |
| 7 | [Debian 13 — containers-storage.conf][7] |
| 8 | [Podman — system service][8] |
| 9 | [s6-rc — 상태 전환·readiness][9] |
| 10 | [s6-rc-update — 실행 중 서비스 정의 교체][10] |
| 11 | [Debian 13 — invoke-rc.d·서비스 정책][11] |
| 12 | [XDG Base Directory Specification][12] |
| 13 | [Wayland Client API][13] |

[1]: https://github.com/ParkSnoopy/ubuntu-slim-zsh "ubuntu-slim-zsh: README와 Dockerfile"
[2]: https://github.com/just-containers/s6-overlay "s6-overlay: init, CMD, 서비스 및 종료"
[3]: https://manpages.debian.org/trixie/sudo/sudoers.5.en.html "Debian 13 sudoers"
[4]: https://docs.podman.io/en/latest/markdown/podman-run.1.html "Podman run: user namespace, 사용자, 장치, 그룹, 네트워크"
[5]: https://manpages.debian.org/trixie/util-linux/setpriv.1.en.html "Debian 13 setpriv"
[6]: https://manpages.debian.org/trixie/golang-github-containers-common/containers.conf.5.en.html "Debian 13 containers.conf"
[7]: https://manpages.debian.org/trixie/containers-storage/containers-storage.conf.5.en.html "Debian 13 containers-storage.conf"
[8]: https://docs.podman.io/en/latest/markdown/podman-system-service.1.html "Podman API의 직접 실행과 보안"
[9]: https://www.skarnet.org/software/s6-rc/s6-rc.html "s6-rc 상태 전환과 readiness"
[10]: https://skarnet.org/software/s6-rc/s6-rc-update.html "s6-rc 실행 중 데이터베이스 교체"
[11]: https://manpages.debian.org/trixie/init-system-helpers/invoke-rc.d.8.en.html "Debian 서비스 실행 정책"
[12]: https://specifications.freedesktop.org/basedir/latest/ "XDG Base Directory Specification"
[13]: https://wayland.freedesktop.org/docs/html/apb.html "Wayland Client API"
