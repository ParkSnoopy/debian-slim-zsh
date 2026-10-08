FROM debian:testing-slim

ARG S6_OVERLAY_VERSION=3.2.3.2

ENV LANG=en_US.UTF-8 \
	S6_BEHAVIOUR_IF_STAGE2_FAILS=2

USER root

COPY rootfs/ /

RUN chmod 755 /usr/sbin/policy-rc.d /usr/local/bin/as-admin && \
	apt-get update && \
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		ca-certificates curl locales procps sudo tmux tzdata util-linux xz-utils zsh && \
	echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen && \
	locale-gen && \
	rm -rf /var/lib/apt/lists/*

RUN set -eu; \
	case "$(dpkg --print-architecture)" in \
		amd64) arch=x86_64; checksum=e6befcc96a437a3831386ecfc51808c5d3e939dc5fe3c02ae9284599e8aa2408 ;; \
		arm64) arch=aarch64; checksum=b17f17a82e7a515c682a91edaf2ffdabb73f891981b6c1fd712115693a2f8b4c ;; \
		*) echo 'Unsupported s6-overlay architecture' >&2; exit 1 ;; \
	esac; \
	url="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"; \
	cd /tmp; \
	curl -fsSL "$url/s6-overlay-noarch.tar.xz" -o s6-overlay-noarch.tar.xz; \
	curl -fsSL "$url/s6-overlay-$arch.tar.xz" -o s6-overlay-arch.tar.xz; \
	echo '5379750ed30a84bbd2e2dd74847ba6b5bd29cd0b2e3ea2ec58049b57eb2eda12  s6-overlay-noarch.tar.xz' | sha256sum -c -; \
	echo "$checksum  s6-overlay-arch.tar.xz" | sha256sum -c -; \
	tar -C / -Jxpf s6-overlay-noarch.tar.xz; \
	tar -C / -Jxpf s6-overlay-arch.tar.xz; \
	rm s6-overlay-noarch.tar.xz s6-overlay-arch.tar.xz; \
	mkdir -p /usr/local/share/debian-slim-zsh; \
	echo "$S6_OVERLAY_VERSION" > /usr/local/share/debian-slim-zsh/s6-overlay-version

COPY src/init.sh src/.zshenv src/.zshrc /etc/skel/
COPY src/_init.sh /usr/local/share/zsh/site-functions/_init.sh
COPY init.sh /usr/local/share/debian-slim-zsh/init.sh
COPY init.d/ /usr/local/share/debian-slim-zsh/init.d/

RUN chmod 755 /etc/skel/init.sh && \
	groupadd --gid 1000 admin && \
	useradd --uid 1000 --gid 1000 --create-home --shell /usr/bin/zsh admin && \
	chmod 440 /etc/sudoers.d/admin && \
	visudo -cf /etc/sudoers && \
	dpkg-query -W > /usr/local/share/debian-slim-zsh/packages.tsv

WORKDIR /home/admin
ENTRYPOINT ["/init"]
CMD ["/usr/local/bin/as-admin", "/usr/bin/zsh", "-l"]
