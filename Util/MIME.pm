use strict;
#-------------------------------------------------------------------------------
# get MIME type
#							(C)2022 nabe@abk
#-------------------------------------------------------------------------------
package Sakia::Util::MIME;
our $VERSION = '1.00';
################################################################################
# constructor
################################################################################
sub new {
	return bless({__CACHE_PM => 1}, shift);
}

#-------------------------------------------------------------------------------
# get mime
#-------------------------------------------------------------------------------
my $DATA;
my %TYPE;

sub get_type {
	my $self = ref($_[0]) eq __PACKAGE__ && shift;
	my $file = shift;

	if (!%TYPE) { &init(); }

	my $ext = $file =~ /\.(\w+)$/ ? $1 : $file;
	return $TYPE{$ext};
}

sub init {
	foreach(split(/\n/, $DATA)) {
		my ($type, @ext) = split(/\s+/, $_);
		foreach(@ext) {
			$TYPE{$_}=$type;
		}
	}
}

#-------------------------------------------------------------------------------
# MIME data
#-------------------------------------------------------------------------------
$DATA=<<'DATA';
application/A2L					a2l
application/AML					aml
application/andrew-inset			ez
application/annodex				anx
application/ATF					atf
application/ATFX				atfx
application/atomcat+xml				atomcat
application/atomdeleted+xml			atomdeleted
application/atomserv+xml			atomsrv
application/atomsvc+xml				atomsvc
application/atom+xml				atom
application/atsc-dwd+xml			dwd
application/atsc-held+xml			held
application/atsc-rsat+xml			rsat
application/ATXML				atxml
application/auth-policy+xml			apxml
application/bacnet-xdd+zip			xdd
application/bbolin				lin
application/calendar+xml			xcs
application/cbor				cbor
application/cccex				c3ex
application/ccmp+xml				ccmp
application/ccxml+xml				ccxml
application/CDFX+XML				cdfx
application/cdmi-capability			cdmia
application/cdmi-container			cdmic
application/cdmi-domain				cdmid
application/cdmi-object				cdmio
application/cdmi-queue				cdmiq
application/CEA					cea
application/cellml+xml				cellml cml
application/clue_info+xml			clue
application/cms					cmsc
application/cpl+xml				cpl
application/csrattrs				csrattrs
application/cu-seeme				cu
application/dashdelta				mpdd
application/dash+xml				mpd
application/davmount+xml			davmount
application/DCD					dcd
application/dicom				dcm
application/DII					dii
application/DIT					dit
application/dskpp+xml				xmls
application/dsptype				tsp
application/dssc+der				dssc
application/dssc+xml				xdssc
application/dvcs				dvc
application/ecmascript				es
application/efi					efi
application/emma+xml				emma
application/emotionml+xml			emotionml
application/epub+zip				epub
application/exi					exi
application/fastinfoset				finf
application/fdt+xml				fdt
application/font-tdpfr				pfr
application/futuresplash			spl
application/geo+json				geojson
application/geopackage+sqlite3			gpkg
application/gltf-buffer				glbin glbuf
application/gml+xml				gml
application/gzip				gz
application/hta					hta
application/hyperstudio				stk
application/inkml+xml				ink inkml
application/ipfix				ipfix
application/its+xml				its
application/java-archive			jar
application/javascript				js mjs
application/java-serialized-object		ser
application/java-vm				class
application/jrd+json				jrd
application/json				json
application/json-patch+json			json-patch
application/ld+json				jsonld
application/lgr+xml				lgr
application/link-format				wlnk
application/lostsync+xml			lostsyncxml
application/lost+xml				lostxml
application/lpf+zip				lpf
application/LXF					lxf
application/m3g					m3g
application/mac-binhex40			hqx
application/mac-compactpro			cpt
application/mads+xml				mads
application/marc				mrc
application/marcxml+xml				mrcx
application/mathematica				ma mb
application/mathml+xml				mml
application/mbox				mbox
application/metalink4+xml			meta4
application/mets+xml				mets
application/MF4					mf4
application/mmt-aei+xml				maei
application/mmt-usd+xml				musd
application/mods+xml				mods
application/mp21				m21 mp21
application/msaccess				mdb
application/msword				doc
application/mxf					mxf
application/n-quads				nq
application/n-triples				nt
application/ocsp-request			orq
application/ocsp-response			ors
application/octet-stream			bin deploy msu msp
application/oda					oda
application/ODX					odx
application/oebps-package+xml			opf
application/ogg					ogx
application/onenote				one onetoc2 onetmp onepkg
application/oxps				oxps
application/p2p-overlay+xml			relo
application/pdf					pdf
application/PDX					pdx
application/pem-certificate-chain		pem
application/pgp-encrypted			pgp
application/pgp-keys				asc key
application/pgp-signature			sig
application/pics-rules				prf
application/pkcs10				p10
application/pkcs12				p12 pfx
application/pkcs7-mime				p7m p7c p7z
application/pkcs7-signature			p7s
application/pkcs8				p8
application/pkcs8-encrypted			p8e
application/pkix-attr-cert			ac
application/pkix-cert				cer
application/pkixcmp				pki
application/pkix-crl				crl
application/pkix-pkipath			pkipath
application/postscript				ps ai eps epsi epsf eps2 eps3
application/provenance+xml			provx
application/prs.cww				cw cww
application/prs.hpub+zip			hpub
application/prs.nprend				rnd rct
application/prs.rdf-xml-crypt			rdf-crypt
application/prs.xsf+xml				xsf
application/pskc+xml				pskcxml
application/rdf+xml				rdf
application/reginfo+xml				rif
application/relax-ng-compact-syntax		rnc
application/resource-lists-diff+xml		rld
application/resource-lists+xml			rl
application/rfc+xml				rfcxml
application/rls-services+xml			rs
application/route-apd+xml			rapd
application/route-s-tsid+xml			sls
application/route-usd+xml			rusd
application/rpki-ghostbusters			gbr
application/rpki-manifest			mft
application/rpki-roa				roa
application/rtf					rtf
application/scim+json				scim
application/scvp-cv-request			scq
application/scvp-cv-response			scs
application/scvp-vp-request			spq
application/scvp-vp-response			spp
application/sdp					sdp
application/senml+cbor				senmlc
application/senml-etch+cbor			senml-etchc
application/senml-etch+json			senml-etchj
application/senml-exi				senmle
application/senml+json				senml
application/senml+xml				senmlx
application/sensml+cbor				sensmlc
application/sensml-exi				sensmle
application/sensml+json				sensml
application/sensml+xml				sensmlx
application/sgml-open-catalog			soc
application/shf+xml				shf
application/sieve				siv sieve
application/simple-filter+xml			cl
application/smil+xml				smil smi sml
application/sparql-query			rq
application/sparql-results+xml			srx
application/sql					sql
application/srgs				gram
application/srgs+xml				grxml
application/sru+xml				sru
application/ssml+xml				ssml
application/stix+json				stix
application/swid+xml				swidtag
application/tamp-apex-update			tau
application/tamp-apex-update-confirm		auc
application/tamp-community-update		tcu
application/tamp-community-update-confirm	cuc
application/tamp-error				ter
application/tamp-sequence-adjust		tsa
application/tamp-sequence-adjust-confirm	sac
application/tamp-update				tur
application/tamp-update-confirm			tuc
application/td+json				jsontd
application/tei+xml				tei teiCorpus odd
application/thraud+xml				tfi
application/timestamped-data			tsd
application/timestamp-query			tsq
application/timestamp-reply			tsr
application/trig				trig
application/ttml+xml				ttml
application/urc-grpsheet+xml			gsheet
application/urc-ressheet+xml			rsheet
application/urc-targetdesc+xml			td
application/urc-uisocketdesc+xml		uis
application/vnd.1000minds.decision-model+xml	1km
application/vnd.3gpp2.sms			sms
application/vnd.3gpp2.tcap			tcap
application/vnd.3gpp.pic-bw-large		plb
application/vnd.3gpp.pic-bw-small		psb
application/vnd.3gpp.pic-bw-var			pvb
application/vnd.3lightssoftware.imagescal	imgcal
application/vnd.3M.Post-it-Notes		pwn
application/vnd.accpac.simply.aso		aso
application/vnd.accpac.simply.imp		imp
application/vnd.acucobol			acu
application/vnd.acucorp				atc acutc
application/vnd.adobe.flash.movie		swf
application/vnd.adobe.formscentral.fcdt		fcdt
application/vnd.adobe.fxp			fxp fxpl
application/vnd.adobe.xdp+xml			xdp
application/vnd.adobe.xfdf			xfdf
application/vnd.afpc.modca			list3820 listafp afp pseg3820
application/vnd.afpc.modca-overlay		ovl
application/vnd.afpc.modca-pagesegment		psg
application/vnd.ahead.space			ahead
application/vnd.airzip.filesecure.azf		azf
application/vnd.airzip.filesecure.azs		azs
application/vnd.amazon.mobi8-ebook		azw3
application/vnd.americandynamics.acc		acc
application/vnd.amiga.ami			ami
application/vnd.android.ota			ota
application/vnd.android.package-archive						apk
application/vnd.anki				apkg
application/vnd.anser-web-certificate-issue-initiation	cii
application/vnd.anser-web-funds-transfer-initiation	fti
application/vnd.apple.installer+xml		dist distz pkg mpkg
application/vnd.apple.keynote			keynote
application/vnd.apple.mpegurl			m3u8
application/vnd.apple.numbers			numbers
application/vnd.apple.pages			pages
application/vnd.aristanetworks.swi		swi
application/vnd.artisan+json			artisan
application/vnd.astraea-software.iota		iota
application/vnd.audiograph			aep
application/vnd.autopackage			package
application/vnd.balsamiq.bmml+xml		bmml
application/vnd.balsamiq.bmpr			bmpr
application/vnd.banana-accounting		ac2
application/vnd.blueice.multipass		mpm
application/vnd.bluetooth.ep.oob		ep
application/vnd.bluetooth.le.oob		le
application/vnd.bmi				bmi
application/vnd.businessobjects			rep
application/vnd.cendio.thinlinc.clientconf	tlclient
application/vnd.chemdraw+xml			cdxml
application/vnd.chess-pgn			pgn
application/vnd.chipnuts.karaoke-mmd		mmd
application/vnd.cinderella			cdy
application/vnd.citationstyles.style+xml	csl
application/vnd.claymore			cla
application/vnd.cloanto.rp9			rp9
application/vnd.clonk.c4group			c4g c4d c4f c4p c4u
application/vnd.cluetrust.cartomobile-config	c11amc
application/vnd.cluetrust.cartomobile-config-pkg	c11amz
application/vnd.coffeescript			coffee
application/vnd.collabio.xodocuments.document	xodt
application/vnd.collabio.xodocuments.document-template	xott
application/vnd.collabio.xodocuments.presentation	xodp
application/vnd.collabio.xodocuments.presentation-template	xotp
application/vnd.collabio.xodocuments.spreadsheet	xods
application/vnd.collabio.xodocuments.spreadsheet-template	xots
application/vnd.comicbook-rar			cbr
application/vnd.comicbook+zip			cbz
application/vnd.commerce-battelle		icf icd ic0 ic1 ic2 ic3 ic4 ic5 ic6 ic7 ic8
application/vnd.commonspace			csp cst
application/vnd.contact.cmsg			cdbcmsg
application/vnd.coreos.ignition+json		ign ignition
application/vnd.cosmocaller			cmc
application/vnd.crick.clicker			clkx
application/vnd.crick.clicker.keyboard		clkk
application/vnd.crick.clicker.palette		clkp
application/vnd.crick.clicker.template		clkt
application/vnd.crick.clicker.wordbank		clkw
application/vnd.criticaltools.wbs+xml		wbs
application/vnd.crypto-shade-file		ssvc
application/vnd.ctc-posml			pml
application/vnd.cups-ppd			ppd
application/vnd.dart				dart
application/vnd.data-vision.rdz			rdz
application/vnd.dbf				dbf
application/vnd.debian.binary-package		deb ddeb udeb
application/vnd.dece.data			uvf uvvf uvd uvvd
application/vnd.dece.ttml+xml			uvt uvvt
application/vnd.dece.unspecified		uvx uvvx
application/vnd.dece.zip			uvz uvvz
application/vnd.denovo.fcselayout-link		fe_launch
application/vnd.desmume.movie			dsm
application/vnd.dna				dna
application/vnd.document+json			docjson
application/vnd.doremir.scorecloud-binary-document	scld
application/vnd.dpgraph				dpg mwc dpgraph
application/vnd.dreamfactory			dfac
application/vnd.dtg.local.flash			fla
application/vnd.dvb.ait				ait
application/vnd.dvb.service			svc
application/vnd.dynageo				geo
application/vnd.dzr				dzr
application/vnd.ecowin.chart			mag
application/vnd.enliven				nml
application/vnd.epson.esf			esf
application/vnd.epson.msf			msf
application/vnd.epson.quickanime		qam
application/vnd.epson.salt			slt
application/vnd.epson.ssf			ssf
application/vnd.ericsson.quickcall		qcall qca
application/vnd.espass-espass+zip		espass
application/vnd.eszigno3+xml			es3 et3
application/vnd.etsi.asic-e+zip			asice sce
application/vnd.etsi.asic-s+zip			asics
application/vnd.etsi.timestamp-token		tst
application/vnd.evolv.ecig.profile		ecigprofile
application/vnd.evolv.ecig.settings		ecig
application/vnd.evolv.ecig.theme		ecigtheme
application/vnd.exstream-empower+zip		mpw
application/vnd.exstream-package		pub
application/vnd.ezpix-album			ez2
application/vnd.ezpix-package			ez3
application/vnd.fastcopy-disk-image		dim
application/vnd.fdf				fdf
application/vnd.fdsn.mseed			msd mseed
application/vnd.fdsn.seed			seed dataless
application/vnd.ficlab.flb+zip			flb
application/vnd.filmit.zfc			zfc
application/vnd.FloGraphIt			gph
application/vnd.fluxtime.clip			ftc
application/vnd.font-fontforge-sfd		sfd
application/vnd.framemaker			fm
application/vnd.fsc.weblaunch			fsc
application/vnd.fujitsu.oasys			oas
application/vnd.fujitsu.oasys2			oa2
application/vnd.fujitsu.oasys3			oa3
application/vnd.fujitsu.oasysgp			fg5
application/vnd.fujitsu.oasysprs		bh2
application/vnd.fujixerox.ddd			ddd
application/vnd.fujixerox.docuworks		xdw
application/vnd.fujixerox.docuworks.binder	xbd
application/vnd.fujixerox.docuworks.container	xct
application/vnd.fuzzysheet			fzs
application/vnd.genomatix.tuxedo		txd
application/vnd.geogebra.file			ggb
application/vnd.geogebra.tool			ggt
application/vnd.geometry-explorer		gex gre
application/vnd.geonext				gxt
application/vnd.geoplan				g2w
application/vnd.geospace			g3w
application/vnd.google-earth.kml+xml		kml
application/vnd.google-earth.kmz		kmz
application/vnd.grafeq				gqf gqs
application/vnd.groove-account			gac
application/vnd.groove-help			ghf
application/vnd.groove-identity-message		gim
application/vnd.groove-injector			grv
application/vnd.groove-tool-message		gtm
application/vnd.groove-tool-template		tpl
application/vnd.groove-vcard			vcg
application/vnd.hal+xml				hal
application/vnd.HandHeld-Entertainment+xml	zmm
application/vnd.hbci				hbci hbc kom upa pkd bpd
application/vnd.hdt				hdt
application/vnd.hhe.lesson-player		les
application/vnd.hp-HPGL				hpgl
application/vnd.hp-hpid				hpi hpid
application/vnd.hp-hps				hps
application/vnd.hp-jlyt				jlt
application/vnd.hp-PCL				pcl
application/vnd.hydrostatix.sof-data		sfd-hdstx
application/vnd.ibm.electronic-media		emm
application/vnd.ibm.MiniPay			mpy
application/vnd.ibm.rights-management		irm
application/vnd.ibm.secure-container		sc
application/vnd.iccprofile			icc icm
application/vnd.ieee.1905			1905.1
application/vnd.igloader			igl
application/vnd.imagemeter.folder+zip		imf
application/vnd.imagemeter.image+zip		imi
application/vnd.immervision-ivp			ivp
application/vnd.immervision-ivu			ivu
application/vnd.ims.imsccv1p1			imscc
application/vnd.insors.igm			igm
application/vnd.intercon.formnet		xpw xpx
application/vnd.intergeo			i2g
application/vnd.intu.qbo			qbo
application/vnd.intu.qfx			qfx
application/vnd.ipunplugged.rcprofile		rcprofile
application/vnd.irepository.package+xml		irp
application/vnd.isac.fcs			fcs
application/vnd.is-xpr				xpr
application/vnd.jam				jam
application/vnd.jcp.javame.midlet-rms		rms
application/vnd.jisp				jisp
application/vnd.joost.joda-archive		joda
application/vnd.kahootz				ktz ktr
application/vnd.kde.karbon			karbon
application/vnd.kde.kchart			chrt
application/vnd.kde.kformula			kfo
application/vnd.kde.kivio			flw
application/vnd.kde.kontour			kon
application/vnd.kde.kpresenter			kpr kpt
application/vnd.kde.kspread			ksp
application/vnd.kde.kword			kwd kwt
application/vnd.kenameaapp			htke
application/vnd.kidspiration			kia
application/vnd.Kinar				kne knp sdf
application/vnd.koan				skp skd skm skt
application/vnd.kodak-descriptor		sse
application/vnd.las.las+json			lasjson
application/vnd.las.las+xml			lasxml
application/vnd.llamagraphics.life-balance.desktop	lbd
application/vnd.llamagraphics.life-balance.exchange+xml	lbe
application/vnd.logipipe.circuit+zip		lcs lca
application/vnd.loom				loom
application/vnd.lotus-1-2-3			123 wk4 wk3 wk1
application/vnd.lotus-approach			apr vew
application/vnd.lotus-freelance			prz pre
application/vnd.lotus-notes			nsf ntf ndl ns4 ns3 ns2 nsh nsg
application/vnd.lotus-organizer			or3 or2 org
application/vnd.lotus-screencam			scm
application/vnd.lotus-wordpro			lwp sam
application/vnd.macports.portpkg		portpkg
application/vnd.mapbox-vector-tile		mvt
application/vnd.marlin.drm.mdcf			mdc
application/vnd.maxmind.maxmind-db		mmdb
application/vnd.mcd				mcd
application/vnd.medcalcdata			mc1
application/vnd.mediastation.cdkey		cdkey
application/vnd.MFER				mwf
application/vnd.mfmp				mfm
application/vnd.micrografx.flo			flo
application/vnd.micrografx.igx			igx
application/vnd.mif				mif
application/vnd.Mobius.DAF			daf
application/vnd.Mobius.DIS			dis
application/vnd.Mobius.MBK			mbk
application/vnd.Mobius.MQY			mqy
application/vnd.Mobius.MSL			msl
application/vnd.Mobius.PLC			plc
application/vnd.Mobius.TXF			txf
application/vnd.mophun.application		mpn
application/vnd.mophun.certificate		mpc
application/vnd.mozilla.xul+xml			xul
application/vnd.ms-3mfdocument			3mf
application/vnd.msa-disk-image			msa
application/vnd.ms-artgalry			cil
application/vnd.ms-asf				asf
application/vnd.ms-cab-compressed		cab
application/vnd.mseq				mseq
application/vnd.ms-excel			xls xlm xla xlc xlt xlw
application/vnd.ms-excel.addin.macroEnabled.12	xlam
application/vnd.ms-excel.sheet.binary.macroEnabled.12	xlsb
application/vnd.ms-excel.sheet.macroEnabled.12	xlsm
application/vnd.ms-excel.template.macroEnabled.12	xltm
application/vnd.ms-fontobject			eot
application/vnd.ms-htmlhelp			chm
application/vnd.ms-ims				ims
application/vnd.ms-lrm				lrm
application/vnd.ms-officetheme			thmx
application/vnd.ms-pki.seccat			cat
#application/vnd.ms-pki.stl							stl
application/vnd.ms-powerpoint							ppt pps
application/vnd.ms-powerpoint.addin.macroEnabled.12				ppam
application/vnd.ms-powerpoint.presentation.macroEnabled.12			pptm
application/vnd.ms-powerpoint.slide.macroEnabled.12				sldm
application/vnd.ms-powerpoint.slideshow.macroEnabled.12				ppsm
application/vnd.ms-powerpoint.template.macroEnabled.12				potm
application/vnd.ms-project			mpp mpt
application/vnd.ms-tnef				tnef tnf
application/vnd.ms-word.document.macroEnabled.12				docm
application/vnd.ms-word.template.macroEnabled.12				dotm
application/vnd.ms-works			wcm wdb wks wps
application/vnd.ms-wpl				wpl
application/vnd.ms-xpsdocument			xps
application/vnd.multiad.creator			crtr
application/vnd.multiad.creator.cif		cif
application/vnd.musician			mus
application/vnd.muvee.style			msty
application/vnd.mynfc				taglet
application/vnd.nervana				entity request bkm kcm
application/vnd.neurolanguage.nlu		nlu
application/vnd.nimn				nimn
application/vnd.nintendo.nitro.rom		nds
application/vnd.nintendo.snes.rom		sfc smc
application/vnd.nitf				nitf
application/vnd.noblenet-directory		nnd
application/vnd.noblenet-sealer			nns
application/vnd.noblenet-web			nnw
application/vnd.nokia.n-gage.data		ngdat
application/vnd.nokia.radio-preset		rpst
application/vnd.nokia.radio-presets		rpss
application/vnd.novadigm.EDM			edm
application/vnd.novadigm.EDX			edx
application/vnd.novadigm.EXT			ext
application/vnd.oasis.opendocument.chart					odc
application/vnd.oasis.opendocument.chart-template				otc
application/vnd.oasis.opendocument.database					odb
application/vnd.oasis.opendocument.formula					odf
application/vnd.oasis.opendocument.graphics					odg
application/vnd.oasis.opendocument.graphics-template				otg
application/vnd.oasis.opendocument.image					odi
application/vnd.oasis.opendocument.image-template				oti
application/vnd.oasis.opendocument.presentation					odp
application/vnd.oasis.opendocument.presentation-template			otp
application/vnd.oasis.opendocument.spreadsheet					ods
application/vnd.oasis.opendocument.spreadsheet-template				ots
application/vnd.oasis.opendocument.text						odt
application/vnd.oasis.opendocument.text-master					odm
application/vnd.oasis.opendocument.text-template				ott
application/vnd.oasis.opendocument.text-web					oth
application/vnd.olpc-sugar			xo
application/vnd.oma.dd2+xml			dd2
application/vnd.onepager			tam
application/vnd.onepagertamp			tamp
application/vnd.onepagertamx			tamx
application/vnd.onepagertat			tat
application/vnd.onepagertatp			tatp
application/vnd.onepagertatx			tatx
application/vnd.openblox.game-binary		obg
application/vnd.openblox.game+xml		obgx
application/vnd.openeye.oeb			oeb
application/vnd.openofficeorg.extension		oxt
application/vnd.openstreetmap.data+xml		osm
application/vnd.openxmlformats-officedocument.presentationml.presentation	pptx
application/vnd.openxmlformats-officedocument.presentationml.slide		sldx
application/vnd.openxmlformats-officedocument.presentationml.slideshow		ppsx
application/vnd.openxmlformats-officedocument.presentationml.template		potx
application/vnd.openxmlformats-officedocument.spreadsheetml.sheet		xlsx
application/vnd.openxmlformats-officedocument.spreadsheetml.template		xltx
application/vnd.openxmlformats-officedocument.wordprocessingml.document		docx
application/vnd.openxmlformats-officedocument.wordprocessingml.template		dotx
application/vnd.osa.netdeploy			ndc
application/vnd.osgeo.mapguide.package		mgp
application/vnd.osgi.dp				dp
application/vnd.osgi.subsystem			esa
application/vnd.oxli.countgraph			oxlicg
application/vnd.palm				prc pdb pqa oprc
application/vnd.panoply				plp
application/vnd.patentdive			dive
application/vnd.pawaafile			paw
application/vnd.pg.format			str
application/vnd.pg.osasli			ei6
application/vnd.piaccess.application-license	pil
application/vnd.picsel				efif
application/vnd.pmi.widget			wg
application/vnd.pocketlearn			plf
application/vnd.powerbuilder6			pbd
application/vnd.preminet			preminet
application/vnd.previewsystems.box		box vbox
application/vnd.proteus.magazine		mgz
application/vnd.psfs				psfs
application/vnd.publishare-delta-tree		qps
application/vnd.pvi.ptid1			ptid
application/vnd.qualcomm.brew-app-res		bar
application/vnd.Quark.QuarkXPress		qxd qxt qwd qwt qxl qxb
application/vnd.quobject-quoxdocument		quox quiz
application/vnd.rainstor.data			tree
application/vnd.rar				rar
application/vnd.realvnc.bed			bed
application/vnd.recordare.musicxml		mxl
application/vnd.rig.cryptonote			cryptonote
application/vnd.rim.cod								cod
application/vnd.route66.link66+xml		link66
application/vnd.sailingtracker.track		st
application/vnd.sar				SAR
application/vnd.scribus				scd sla slaz
application/vnd.sealed.3df			s3df
application/vnd.sealed.csf			scsf
application/vnd.sealed.doc			sdoc sdo s1w
application/vnd.sealed.eml			seml sem
application/vnd.sealedmedia.softseal.html	stml s1h
application/vnd.sealedmedia.softseal.pdf	spdf spd s1a
application/vnd.sealed.mht			smht smh
application/vnd.sealed.ppt			sppt s1p
application/vnd.sealed.tiff			stif
application/vnd.sealed.xls			sxls sxl s1e
application/vnd.seemail				see
application/vnd.sema				sema
application/vnd.semd				semd
application/vnd.semf				semf
application/vnd.shade-save-file			ssv
application/vnd.shana.informed.formdata		ifm
application/vnd.shana.informed.formtemplate	itp
application/vnd.shana.informed.interchange	iif
application/vnd.shana.informed.package		ipk
application/vnd.shp				shp
application/vnd.shx				shx
application/vnd.sigrok.session			sr
application/vnd.SimTech-MindMapper		twd twds
application/vnd.smaf				mmf
application/vnd.smart.notebook			notebook
application/vnd.smart.teacher			teacher
application/vnd.snesdev-page-table		ptrom pt
application/vnd.software602.filler.form+xml	fo
application/vnd.software602.filler.form-xml-zip	zfo
application/vnd.solent.sdkm+xml			sdkm sdkd
application/vnd.spotfire.dxp			dxp
application/vnd.spotfire.sfs			sfs
application/vnd.sqlite3				sqlite sqlite3
application/vnd.stardivision.calc						sdc
application/vnd.stardivision.chart						sds
application/vnd.stardivision.draw						sda
application/vnd.stardivision.impress						sdd
application/vnd.stardivision.writer						sdw
application/vnd.stardivision.writer-global					sgl
application/vnd.stepmania.package		smzip
application/vnd.stepmania.stepchart		sm
application/vnd.sun.wadl+xml			wadl
application/vnd.sun.xml.calc							sxc
application/vnd.sun.xml.calc.template						stc
application/vnd.sun.xml.draw							sxd
application/vnd.sun.xml.draw.template						std
application/vnd.sun.xml.impress							sxi
application/vnd.sun.xml.impress.template					sti
application/vnd.sun.xml.math							sxm
application/vnd.sun.xml.writer							sxw
application/vnd.sun.xml.writer.global						sxg
application/vnd.sun.xml.writer.template						stw
application/vnd.sus-calendar			sus susp
application/vnd.symbian.install							sis
application/vnd.syncml.dmddf+xml		ddf
application/vnd.syncml.dm+wbxml			bdm
application/vnd.syncml.dm+xml			xdm
application/vnd.syncml+xml			xsm
application/vnd.tao.intent-module-archive	tao
application/vnd.tcpdump.pcap			pcap cap dmp
application/vnd.theqvd				qvd
application/vnd.think-cell.ppttc+json		ppttc
application/vnd.tml				vfr viaframe
application/vnd.tmobile-livetv			tmo
application/vnd.trid.tpt			tpt
application/vnd.triscape.mxs			mxs
application/vnd.trueapp				tra
application/vnd.ufdl				ufdl ufd frm
application/vnd.uiq.theme			utz
application/vnd.umajin				umj
application/vnd.unity				unityweb
application/vnd.uoml+xml			uoml uo
application/vnd.uri-map				urim urimap
application/vnd.valve.source.material		vmt
application/vnd.vcx				vcx
application/vnd.vd-study			mxi study-inter model-inter
application/vnd.vectorworks			vwx
application/vnd.veryant.thin			istc isws
application/vnd.ves.encrypted			VES
application/vnd.vidsoft.vidconference		vsc
application/vnd.visio				vsd vst vsw vss
application/vnd.visionary			vis
application/vnd.vsf				vsf
application/vnd.wap.sic				sic
application/vnd.wap.slc				slc
application/vnd.wap.wbxml			wbxml
application/vnd.wap.wmlc			wmlc
application/vnd.wap.wmlscriptc			wmlsc
application/vnd.webturbo			wtb
application/vnd.wfa.p2p				p2p
application/vnd.wfa.wsc				wsc
application/vnd.wmc				wmc
application/vnd.wolfram.mathematica		nb
application/vnd.wolfram.mathematica.package	m
application/vnd.wolfram.player			nbp
application/vnd.wordperfect			wpd
application/vnd.wordperfect5.1							wp5
application/vnd.wqd				wqd
application/vnd.wt.stf				stf
application/vnd.wv.csp+wbxml			wv
application/vnd.xara				xar
application/vnd.xfdl				xfdl xfd
application/vnd.xmpie.cpkg			cpkg
application/vnd.xmpie.dpkg			dpkg
application/vnd.xmpie.ppkg			ppkg
application/vnd.xmpie.xlim			xlim
application/vnd.yamaha.hv-dic			hvd
application/vnd.yamaha.hv-script		hvs
application/vnd.yamaha.hv-voice			hvp
application/vnd.yamaha.openscoreformat		osf
application/vnd.yamaha.smaf-audio		saf
application/vnd.yamaha.smaf-phrase		spf
application/vnd.yaoweme				yme
application/vnd.yellowriver-custom-menu		cmp
application/vnd.zul				zir zirz
application/vnd.zzazz.deck+xml			zaz
application/voicexml+xml			vxml
application/voucher-cms+json			vcj
application/wasm				wasm
application/watcherinfo+xml			wif
application/widget				wgt
application/wsdl+xml				wsdl
application/wspolicy+xml			wspolicy
application/x-123				wk
application/x-7z-compressed			7z
application/x-abiword				abw
application/x-apple-diskimage			dmg
application/x-bcpio				bcpio
application/x-bittorrent			torrent
application/xcap-att+xml			xav
application/xcap-caps+xml			xca
application/xcap-diff+xml			xdf
application/xcap-el+xml				xel
application/xcap-error+xml			xer
application/xcap-ns+xml				xns
application/x-cdf				cdf cda
application/x-cdlink				vcd
application/x-comsol				mph
application/x-cpio				cpio
application/x-csh				csh
application/x-director				dcr dir dxr
application/x-doom				wad
application/x-dvi				dvi
application/x-font				pfa pfb gsf
application/x-font-pcf				pcf pcf.Z
application/x-freemind				mm
application/x-ganttproject			gan
application/x-gnumeric				gnumeric
application/x-go-sgf				sgf
application/x-graphing-calculator		gcf
application/x-gtar				gtar
application/x-gtar-compressed			tgz taz
application/x-hdf				hdf
application/xhtml+xml				xhtml xhtm xht
application/x-hwp				hwp
application/x-ica				ica
application/x-info				info
application/x-internet-signup			ins isp
application/x-iphone				iii
application/x-iso9660-image			iso
application/x-java-jnlp-file			jnlp
application/x-jmol				jmz
application/x-killustrator			kil
application/x-latex				latex
application/x-lha				lha
application/xliff+xml				xlf
application/x-lyx				lyx
application/x-lzh				lzh
application/x-lzx				lzx
application/x-maker				frm maker frame fm fb book fbdoc
application/xml					xml
application/xml-dtd				dtd mod
application/xml-external-parsed-entity		ent
application/x-ms-application			application
application/x-msdos-program			com exe bat dll
application/x-msi				msi
application/x-ms-manifest			manifest
application/x-ms-wmd				wmd
application/x-ms-wmz				wmz
application/x-netcdf				nc
application/x-ns-proxy-autoconfig		pac
application/x-nwc				nwc
application/x-object				o
application/xop+xml				xop
application/x-oz-application			oza
application/x-pkcs7-certreqresp			p7r
application/x-python-code			pyc pyo
application/x-qgis				qgs shp shx
application/x-quicktimeplayer			qtl
application/x-rdp				rdp
application/x-redhat-package-manager		rpm
application/x-rss+xml				rss
application/x-ruby				rb
application/x-scilab				sci sce
application/x-scilab-xcos			xcos
application/x-sh				sh
application/x-shar				shar
application/x-silverlight			scr
application/xslt+xml				xsl xslt
application/xspf+xml				xspf
application/x-stuffit				sit sitx
application/x-sv4cpio				sv4cpio
application/x-sv4crc				sv4crc
application/x-tar				tar
application/x-tcl				tcl
application/x-tex-gf				gf
application/x-texinfo				texinfo texi
application/x-tex-pk				pk
application/x-trash				~ % bak old sik
application/x-troff-man				man
application/x-troff-me				me
application/x-troff-ms				ms
application/x-ustar				ustar
application/xv+xml				mxml xhvml xvml xvm
application/x-wais-source			src
application/x-wingz				wz
application/x-x509-ca-cert			crt
application/x-xcf				xcf
application/x-xfig				fig
application/x-xpinstall				xpi
application/x-xz				xz
application/yang				yang
application/yin+xml				yin
application/zip					zip
application/zstd				zst
audio/32kadpcm					726
audio/aac					adts aac ass
audio/ac3					ac3
audio/AMR					amr AMR
audio/AMR-WB					awb AWB
audio/annodex					axa
audio/asc					acn
audio/ATRAC3					at3 aa3 omg
audio/ATRAC-ADVANCED-LOSSLESS			aal
audio/ATRAC-X					atx
audio/basic					au snd
audio/csound					csd orc sco
audio/dls					dls
audio/EVRC					evc
audio/EVRC-QCP					qcp QCP
audio/EVRCB					evb
audio/EVRCNW					enw
audio/EVRCWB					evw
audio/flac					flac
audio/iLBC					lbc
audio/L16					l16
audio/mhas					mhas
audio/mobile-xmf				mxmf
audio/mpeg					mpga mpega mp1 mp2 mp3 m4a
audio/mpegurl					m3u
audio/ogg					oga ogg opus spx
audio/prs.sid					sid psid
audio/SMV					smv
audio/sofa					sofa
audio/sp-midi					mid
audio/usac					loas xhe
audio/vnd.audiokoz				koz
audio/vnd.dece.audio				uva uvva
audio/vnd.digital-winds				eol
audio/vnd.dolby.mlp				mlp
audio/vnd.dts					dts
audio/vnd.dts.hd				dtshd
audio/vnd.everad.plj				plj
audio/vnd.lucent.voice				lvp
audio/vnd.ms-playready.media.pya		pya
audio/vnd.nortel.vbk				vbk
audio/vnd.nuera.ecelp4800			ecelp4800
audio/vnd.nuera.ecelp7470			ecelp7470
audio/vnd.nuera.ecelp9600			ecelp9600
audio/vnd.presonus.multitrack			multitrack
audio/vnd.rip					rip
audio/vnd.sealedmedia.softseal.mpeg		smp3 smp s1m
audio/x-aiff					aif aiff aifc
audio/x-gsm					gsm
audio/x-ms-wax					wax
audio/x-ms-wma					wma
audio/x-pn-realaudio				ra rm ram
audio/x-scpls					pls
audio/x-sd2					sd2
audio/x-wav					wav
chemical/x-alchemy				alc
chemical/x-cache				cac cache
chemical/x-cache-csf				csf
chemical/x-cactvs-binary			cbin cascii ctab
chemical/x-cdx					cdx
chemical/x-chem3d				c3d
chemical/x-chemdraw				chm
chemical/x-cif					cif
chemical/x-cmdf					cmdf
chemical/x-cml					cml
chemical/x-compass				cpa
chemical/x-crossfire				bsd
chemical/x-csml					csml csm
chemical/x-ctx					ctx
chemical/x-cxf					cxf cef
#chemical/x-daylight-smiles			smi
chemical/x-embl-dl-nucleotide			emb embl
chemical/x-galactic-spc				spc
chemical/x-gamess-input				inp gam gamin
chemical/x-gaussian-checkpoint			fch fchk
chemical/x-gaussian-cube			cub
chemical/x-gaussian-input			gau gjc gjf
chemical/x-gaussian-log				gal
chemical/x-gcg8-sequence			gcg
chemical/x-genbank				gen
chemical/x-hin					hin
chemical/x-isostar				istr ist
chemical/x-jcamp-dx				jdx dx
chemical/x-kinemage				kin
chemical/x-macmolecule				mcm
chemical/x-macromodel-input			mmod
chemical/x-mdl-molfile				mol
chemical/x-mdl-rdfile				rd
chemical/x-mdl-rxnfile				rxn
chemical/x-mdl-sdfile				sd sdf
chemical/x-mdl-tgf				tgf
#chemical/x-mif					mif
chemical/x-mmcif				mcif
chemical/x-mol2					mol2
chemical/x-molconn-Z				b
chemical/x-mopac-graph				gpt
chemical/x-mopac-input				mop mopcrt mpc zmt
chemical/x-mopac-out				moo
chemical/x-mopac-vib				mvb
chemical/x-ncbi-asn1				asn
chemical/x-ncbi-asn1-ascii			prt
chemical/x-ncbi-asn1-binary			val aso
chemical/x-ncbi-asn1-spec			asn
chemical/x-pdb					pdb
chemical/x-rosdal				ros
chemical/x-swissprot				sw
chemical/x-vamas-iso14976			vms
chemical/x-vmd					vmd
chemical/x-xtel					xtel
chemical/x-xyz					xyz
font/collection					ttc
font/otf					otf
font/ttf					ttf
font/woff					woff
font/woff2					woff2
image/aces					exr
image/avci					avci
image/avcs					avcs
image/bmp					bmp
image/cgm					cgm
image/dicom-rle					drle
image/emf					emf
image/fits					fits fit fts
image/gif					gif
image/heic					heic
image/heic-sequence				heics
image/heif					heif
image/heif-sequence				heifs
image/hej2k					hej2
image/hsj2					hsj2
image/ief					ief
image/jls					jls
image/jp2					jp2 jpg2
image/jpeg					jpeg jpg jpe jfif
image/jph					jph
image/jphc					jhc jphc
image/jpm					jpm jpgm
image/jpx					jpx jpf
image/jxr					jxr
image/jxrA					jxra
image/jxrS					jxrs
image/jxs					jxs
image/jxsc					jxsc
image/jxsi					jxsi
image/jxss					jxss
image/ktx					ktx
image/ktx2					ktx2
image/png					png
image/prs.btif					btif btf
image/prs.pti					pti
image/svg+xml					svg svgz
image/t38					t38 T38
image/tiff					tiff tif
image/tiff-fx					tfx
image/vnd.adobe.photoshop			psd
image/vnd.airzip.accelerator.azv		azv
image/vnd.dece.graphic				uvi uvvi uvg uvvg
image/vnd.djvu					djvu djv
image/vnd.dwg					dwg
image/vnd.dxf					dxf
image/vnd.fastbidsheet				fbs
image/vnd.fpx					fpx
image/vnd.fst					fst
image/vnd.fujixerox.edmics-mmr			mmr
image/vnd.fujixerox.edmics-rlc			rlc
image/vnd.globalgraphics.pgb			PGB pgb
image/vnd.microsoft.icon			ico
image/vnd.mozilla.apng				apng
image/vnd.ms-modi				mdi
image/vnd.pco.b16				b16
image/vnd.radiance				hdr rgbe xyze
image/vnd.sealedmedia.softseal.gif		sgif sgi s1g
image/vnd.sealedmedia.softseal.jpg		sjpg sjp s1j
image/vnd.sealed.png				spng spn s1n
image/vnd.tencent.tap				tap
image/vnd.valve.source.texture			vtf
image/vnd.wap.wbmp				wbmp
image/vnd.xiff					xif
image/vnd.zbrush.pcx				pcx
image/wmf					wmf
image/x-canon-cr2				cr2
image/x-canon-crw				crw
image/x-cmu-raster				ras
image/x-coreldraw				cdr
image/x-coreldrawpattern			pat
image/x-coreldrawtemplate			cdt
image/x-corelphotopaint				cpt
image/x-epson-erf				erf
image/x-jg					art
image/x-jng					jng
image/x-nikon-nef				nef
image/x-olympus-orf				orf
image/x-portable-anymap				pnm
image/x-portable-bitmap				pbm
image/x-portable-graymap			pgm
image/x-portable-pixmap				ppm
image/x-rgb					rgb
image/x-xbitmap					xbm
image/x-xpixmap					xpm
image/x-xwindowdump				xwd
message/global					u8msg
message/global-delivery-status			u8dsn
message/global-disposition-notification		u8mdn
message/global-headers				u8hdr
message/rfc822					eml mail art
model/gltf-binary				glb
model/gltf+json					gltf
model/iges					igs iges
model/mesh					msh mesh silo
model/mtl					mtl
model/obj					obj
model/stl					stl
model/vnd.collada+xml				dae
model/vnd.dwf					dwf
model/vnd.gdl					gdl gsm win dor lmp rsm msm ism
model/vnd.gtw					gtw
model/vnd.moml+xml				moml
model/vnd.mts					mts
model/vnd.opengex				ogex
model/vnd.parasolid.transmit.binary		x_b xmt_bin
model/vnd.parasolid.transmit.text		x_t xmt_txt
model/vnd.usdz+zip				usdz
model/vnd.valve.source.compiled-map		bsp
model/vnd.vtu					vtu
model/vrml					wrl vrml
model/x3d+fastinfoset				x3db
model/x3d+vrml					x3dv x3dvz
model/x3d+xml					x3d
multipart/vnd.bint.med-plus			bmed
multipart/voice-message				vpm
text/cache-manifest				appcache manifest
text/calendar					ics ifb
text/css					css
text/csv					csv
text/csv-schema					csvs
text/dns					soa zone
text/h323					323
text/html					html htm shtml
text/iuls					uls
text/jcr-cnd					cnd
text/markdown					md markdown
text/mizar					miz
text/n3						n3
text/plain					txt text pot brf srt
text/provenance-notation			provn
text/prs.fallenstein.rst			rst
text/prs.lines.tag				tag dsc
text/richtext					rtx
text/scriptlet					sct
text/sgml					sgml sgm
text/tab-separated-values			tsv
text/texmacs					tm
text/troff					t tr roff
text/turtle					ttl
text/uri-list					uris uri
text/vcard					vcf vcard
text/vnd.a					a
text/vnd.abc					abc
text/vnd.ascii-art				ascii
text/vnd.curl					curl
text/vnd.debian.copyright			copyright
text/vnd.DMClientScript				dms
text/vnd.esmertec.theme-descriptor		jtd
text/vnd.ficlab.flt				flt
text/vnd.fly					fly
text/vnd.fmi.flexstor				flx
text/vnd.graphviz				gv dot
text/vnd.hgl					hgl
text/vnd.in3d.3dml				3dml 3dm
text/vnd.in3d.spot				spot spo
text/vnd.ms-mediapackage			mpf
text/vnd.net2phone.commcenter.command		ccc
text/vnd.senx.warpscript			mc2
text/vnd.sosi					sos
text/vnd.sun.j2me.app-descriptor		jad
text/vnd.trolltech.linguist			ts
text/vnd.wap.si					si
text/vnd.wap.sl					sl
text/vnd.wap.wml				wml
text/vnd.wap.wmlscript				wmls
text/vtt					vtt
text/x-bibtex					bib
text/x-boo					boo
text/x-c++hdr					h++ hpp hxx hh
text/x-chdr					h
text/x-component				htc
text/x-csh					csh
text/x-c++src					c++ cpp cxx cc
text/x-csrc					c
text/x-diff					diff patch
text/x-dsrc					d
text/x-haskell					hs
text/x-java					java
text/x-lilypond					ly
text/x-literate-haskell				lhs
text/x-moc					moc
text/x-pascal					p pas
text/x-pcs-gcd					gcd
text/x-perl					pl pm
text/x-python					py
text/x-scala					scala
text/x-setext					etx
text/x-sfv					sfv
text/x-sh					sh
text/x-tcl					tcl tk
text/x-tex					tex ltx sty cls
text/x-vcalendar				vcs
video/annodex					axv
video/dl					dl
video/dv					dif dv
video/fli					fli
video/gl					gl
video/iso.segment				m4s
video/mj2					mj2 mjp2
video/mp4					mp4 mpg4 m4v
video/mpeg					mpeg mpg mpe m1v m2v
video/ogg					ogv
video/quicktime					qt mov
video/vnd.dece.hd				uvh uvvh
video/vnd.dece.mobile				uvm uvvm
video/vnd.dece.mp4				uvu uvvu
video/vnd.dece.pd				uvp uvvp
video/vnd.dece.sd				uvs uvvs
video/vnd.dece.video				uvv uvvv
video/vnd.dvb.file				dvb
video/vnd.fvt					fvt
video/vnd.mpegurl				mxu m4u
video/vnd.ms-playready.media.pyv		pyv
video/vnd.nokia.interleaved-multimedia		nim
video/vnd.radgamettools.bink			bik bk2
video/vnd.radgamettools.smacker			smk
video/vnd.sealedmedia.softseal.mov		smov smo s1q
video/vnd.sealed.mpeg1				smpg s11
video/vnd.sealed.mpeg4				s14
video/vnd.sealed.swf				sswf ssw
video/vnd.vivo					viv
video/vnd.youtube.yt				yt
video/webm					webm
video/x-flv					flv
video/x-la-asf					lsf lsx
video/x-matroska				mpv mkv
video/x-mng					mng
video/x-msvideo					avi
video/x-ms-wm					wm
video/x-ms-wmv					wmv
video/x-ms-wmx					wmx
video/x-ms-wvx					wvx
video/x-sgi-movie				movie
x-conference/x-cooltalk				ice
x-epoc/x-sisx-app				sisx
x-world/x-vrml					vrm vrml wrl
DATA

1;
