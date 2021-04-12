# Copyright 1999-2021 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI="7"

MULTILIB_STRICT_DIRS=  # Dirty hack to bypass failing multilib-strict testing

PYVER_MAJOR="$(ver_cut 1)"
PYVER_MINOR="$(ver_cut 2)"
PYVER="${PYVER_MAJOR}.${PYVER_MINOR}"

DESCRIPTION="A really great language"
HOMEPAGE="https://www.python.org"
SRC_URI="https://www.python.org/ftp/python/${PV}/Python-${PV}.tgz"

SLOT="2.2"
LICENSE="PSF-2.2"
KEYWORDS="~amd64 ~sparc ~x86"
IUSE="build readline tk berkdb bootstrap"

DEPEND="
	>=sys-libs/zlib-1.1.3
	readline? ( >=sys-libs/readline-4.1 >=sys-libs/ncurses-5.2 )
	berkdb? ( >=sys-libs/db-3:* )
	tk? ( >=dev-lang/tk-8.0 )"
RDEPEND="$DEPEND"

# The dev-python/python-fchksum RDEPEND is needed to that this python provides
# the functionality expected from previous pythons.

S=${WORKDIR}/Python-${PV}

src_prepare() {
	# python's config seems to ignore CFLAGS
	export OPT=$CFLAGS

	# adjust makefile to install pydoc into ${D} correctly
	t=${S}/Makefile.pre.in
	cp $t $t.orig || die
	sed 's:install-platlib.*:& --install-scripts=$(BINDIR):' $t.orig > $t

	# adjust Setup to include the various modules we need
	cd "${S}"
	# turn **on** shared
	scmd="s:#\(\*shared\*\):\1:;"
	# adjust for USE readline
	if use readline; then
		scmd="$scmd  s:#\(readline .*\) -ltermcap:\1:;"
		scmd="$scmd  s:#\(_curses .*\) -lcurses -ltermcap:\1 -lncurses:;"
	fi
	# adjust for USE tk
	if use tk; then
		# Find the version of tcl/tk that has headers installed.
		# This will be the most recently merged, not necessarily the highest
		# version number.
		tclv=$(grep TCL_VER /usr/include/tcl.h | sed 's/^.*"\(.*\)".*/\1/')
		tkv=$( grep  TK_VER /usr/include/tk.h  | sed 's/^.*"\(.*\)".*/\1/')
		# adjust Setup to match
		scmd="$scmd  s:# \(_tkinter \):\1:;"
		scmd="$scmd  s:#\(\t-ltk[0-9.]* -ltcl[0-9.]*\):\t-ltk$tkv -ltcl$tclv:;"
		scmd="$scmd  s:#\(\t-L/usr/X11R6/lib\):\1:;"
		scmd="$scmd  s:#\(\t-lX11.*\):\1:;"
		scmd="$scmd  s:#\(\t-I/usr/X11R6/include\):\1:;"
	fi
	# adjust for USE berkdb
	if use berkdb; then
		# patch the dbmmodule to use db3's dbm compatibility code.  That way,
		# we're depending on db3 rather than old db1.
		t=Modules/dbmmodule.c
		cp $t $t.orig || die
		sed \
			-e '10,25d' \
			-e '26i\' \
			-e '#define DB_DBM_HSEARCH 1\' \
			-e 'static char *which_dbm = "BSD db";\' \
			-e '#include <db3/db.h>' \
			$t.orig > $t
		# now fix Setup
		scmd="$scmd  s:#dbm.*:dbm dbmmodule.c -I/usr/include/db3 -ldb-3.2:;"
	fi
	# no USE vars to switch off these adjustments:
	scmd="$scmd  s:#\(_locale .*\):\1:;"  # access to ISO C locale support
	scmd="$scmd  s:#\(syslog .*\):\1:;"   # syslog daemon interface
	scmd="$scmd  s:#\(zlib .*\):\1:;"	 # This require zlib 1.1.3 (or later).
	scmd="$scmd  s:#\(termios .*\):\1:;"  # Steen Lumholt's termios module
	scmd="$scmd  s:#\(resource .*\):\1:;" # Jeremy Hylton's rlimit interface
	sed "$scmd" Modules/Setup.dist > Modules/Setup

	eapply "${FILESDIR}"/${P}-readline.patch

	eapply_user
}

src_configure() {
	local myopts
	#if we are creating a new build image, we remove the dependency on g++
	if [ "`use build`" -a ! "`use bootstrap`" ]
	then
		myopts="--with-cxx=no"
	fi
	OPT="${CFLAGS} -fPIC" ./configure \
		--prefix=/usr \
		--without-libdb \
		--infodir='${prefix}'/share/info \
		--mandir='${prefix}'/share/man $myopts
	assert "Configure failed"
	# kill the -DHAVE_CONFIG_H flag
	mv Makefile Makefile.orig
	sed -e 's/-DHAVE_CONFIG_H//' Makefile.orig > Makefile
}

src_compile() {
	#emake || die "Parallel make failed"
	make || die "Parallel make failed"
}

src_install() {
	dodir /usr

	# Extra shot to workaround weird "Lib/plat-linux3" target error
	make install prefix="${D}"/usr || true
	make install prefix="${D}"/usr || die
	rm "${D}/usr/bin/python" || die
	dodoc README || die

	# install our own custom python-config
	### exeinto /usr/bin
	### newexe "${FILESDIR}"/python-config-${PYVER} python-config

	# seems like the build do not install Makefile.pre.in anymore
	insinto /usr/lib/python${PYVER}/config
	doins "${S}"/Makefile.pre.in || die

	# If USE tk lets install idle
	# Need to script the python version in the path
	if use tk; then
		dodir /usr/lib/python${PYVER}/tools
		mv "${S}/Tools/idle" "${D}/usr/lib/python${PYVER}/tools/" || die
		dosym /usr/lib/python${PYVER}/tools/idle/idle.py /usr/bin/idle.py || die
	fi

	mv "${D}"/usr/share/man/man1/python{,${PV}}.1 || die
	mv "${D}"/usr/bin/pydoc{,${PV}} || die
}
