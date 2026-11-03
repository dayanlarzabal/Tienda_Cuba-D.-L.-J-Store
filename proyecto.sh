#!/usr/bin/env bash
# HANDMADE D.L.J STORE — genera el proyecto Flutter completo y lo prepara para compilar el APK.
# Se ejecuta desde el workflow de GitHub (build-apk.yml) en la raíz del repositorio.

# ===== DATOS DE TU SERVIDOR (Supabase) =====
# Se leen de las variables del repositorio (SUPABASE_URL y SUPABASE_ANON_KEY).
# Si están vacías, la app funciona en modo local (sin servidor).
SUPABASE_URL="${SUPABASE_URL:-}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}"
# =============================================

set -euo pipefail

SUPABASE_URL="$(echo "${SUPABASE_URL}" | tr -d ' \r\n"')"
SUPABASE_URL="${SUPABASE_URL%/}"
SUPABASE_ANON_KEY="$(echo "${SUPABASE_ANON_KEY}" | tr -d ' \r\n"')"
if [ -n "${SUPABASE_URL}${SUPABASE_ANON_KEY}" ]; then
  case "${SUPABASE_URL}" in https://*) ;; *) echo "ERROR: SUPABASE_URL debe empezar por https://"; exit 1;; esac
  case "${SUPABASE_ANON_KEY}" in eyJ*|sb_publishable_*) ;; *) echo "ERROR: SUPABASE_ANON_KEY no parece una clave anon/publishable válida"; exit 1;; esac
  echo "▶ Modo servidor activado: ${SUPABASE_URL}"
else
  echo "▶ Modo local (sin servidor)"
fi

echo "▶ Creando archivos del proyecto…"
rm -rf lib android
mkdir -p lib/theme lib/models lib/state lib/utils lib/widgets lib/screens lib/data assets/images

cat > lib/config.dart <<DLJ_CFG
// Generado por proyecto.sh con los datos de tu servidor.
const String kSupabaseUrl = '${SUPABASE_URL}';
const String kSupabaseAnonKey = '${SUPABASE_ANON_KEY}';

bool get kRemote => kSupabaseUrl.isNotEmpty && kSupabaseAnonKey.isNotEmpty;
DLJ_CFG
cat > 'lib/data/api.dart' <<'DLJ_EOF_1'
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

double _d(dynamic v) => v == null ? 0 : (double.tryParse(v.toString()) ?? 0);
String _s(dynamic v) => v == null ? '' : v.toString();

Product productFromRow(Map<String, dynamic> m) => Product(
      id: _s(m['id']),
      name: _s(m['name']),
      subtitle: _s(m['subtitle']),
      description: _s(m['description']),
      kind: ProductKind.values.firstWhere(
        (e) => e.name == m['kind'],
        orElse: () => ProductKind.app,
      ),
      priceCUP: _d(m['price_cup']),
      priceMLC: _d(m['price_mlc']),
      priceUSDT: _d(m['price_usdt']),
      imageUrl: _s(m['image_url']),
      downloadUrl: _s(m['download_url']),
      isDigital: m['is_digital'] == null ? true : m['is_digital'] == true,
      badge: _s(m['badge']),
      featured: m['featured'] == true,
      active: m['active'] == null ? true : m['active'] == true,
    );

OrderRecord orderFromRow(Map<String, dynamic> m, {String token = ''}) {
  final items = (m['items'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .map((i) => OrderLine(
            productId: _s(i['product_id']),
            name: _s(i['name']),
            kind: ProductKind.values.firstWhere(
              (e) => e.name == i['kind'],
              orElse: () => ProductKind.app,
            ),
            qty: (_d(i['qty'])).toInt(),
            unitCUP: _d(i['unit_cup']),
            unitMLC: _d(i['unit_mlc']),
            unitUSDT: _d(i['unit_usdt']),
            isDigital: i['is_digital'] == null ? true : i['is_digital'] == true,
            downloadUrl: _s(i['download_url']),
          ))
      .toList();
  return OrderRecord(
    id: _s(m['id']),
    code: _s(m['code']),
    accessToken: token,
    lines: items,
    method: PayMethod.values.firstWhere(
      (e) => e.name == m['method'],
      orElse: () => PayMethod.transfermovilCup,
    ),
    amount: _d(m['amount']),
    reference: _s(m['reference']),
    customerName: _s(m['customer_name']),
    phone: _s(m['phone']),
    address: _s(m['address']),
    fromWallet: _s(m['from_wallet']),
    createdAt: DateTime.tryParse(_s(m['created_at']))?.toLocal() ?? DateTime.now(),
    status: OrderStatus.values.firstWhere(
      (e) => e.name == m['status'],
      orElse: () => OrderStatus.pending,
    ),
    sellerNote: _s(m['seller_note']),
  );
}

/// Cliente del servidor (Supabase: PostgREST + Auth + Storage).
class Api {
  final http.Client _c = http.Client();
  String? _access;
  String? _refresh;

  static const _timeout = Duration(seconds: 25);

  bool get isAdmin => _access != null;

  Map<String, String> _headers({bool json = true}) => {
        'apikey': kSupabaseAnonKey,
        if (_access != null) 'Authorization': 'Bearer $_access',
        if (json) 'Content-Type': 'application/json',
      };

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$kSupabaseUrl$path').replace(queryParameters: query);

  String _errorMessage(http.Response r) {
    var msg = 'Error del servidor (${r.statusCode})';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map) {
        final m = j['message'] ?? j['msg'] ?? j['error_description'] ?? j['error'];
        if (m != null && m.toString().isNotEmpty) msg = m.toString();
      }
    } catch (_) {}
    return msg;
  }

  Future<http.Response> _guard(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on TimeoutException {
      throw ApiException('El servidor tarda demasiado. Revisa tu conexión e inténtalo de nuevo.');
    } on SocketException {
      throw ApiException('Sin conexión. Revisa tu internet e inténtalo de nuevo.');
    } on http.ClientException {
      throw ApiException('Sin conexión. Revisa tu internet e inténtalo de nuevo.');
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() call, {bool retry = true}) async {
    final r = await _guard(call);
    if (r.statusCode == 401 && retry && _refresh != null) {
      await _refreshSession();
      return _send(call, retry: false);
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(r.bodyBytes));
    }
    throw ApiException(_errorMessage(r));
  }

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? args]) => _send(
        () => _c.post(_u('/rest/v1/rpc/$name'),
            headers: _headers(), body: jsonEncode(args ?? <String, dynamic>{})),
      );

  // ─────────── Público ───────────

  Future<List<Product>> fetchProducts() async {
    final j = await _send(() => _c.get(
          _u('/rest/v1/products', {
            'select': '*',
            'active': 'eq.true',
            'order': 'sort.asc,created_at.desc',
          }),
          headers: _headers(json: false),
        ));
    return (j as List).map((e) => productFromRow(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<StoreConfig> fetchSettings() async {
    final j = await _send(() => _c.get(
          _u('/rest/v1/store_settings', {'select': '*', 'id': 'eq.1'}),
          headers: _headers(json: false),
        ));
    final list = j as List;
    if (list.isEmpty) return StoreConfig();
    final m = Map<String, dynamic>.from(list.first as Map);
    return StoreConfig(
      businessName: _s(m['business_name']).isEmpty ? 'HANDMADE D.L.J STORE' : _s(m['business_name']),
      whatsapp: _s(m['whatsapp']),
      cupCard: _s(m['cup_card']),
      mlcCard: _s(m['mlc_card']),
      tronAddress: _s(m['tron_address']),
      trxPerUsdt: _d(m['trx_per_usdt']),
      btcAddress: _s(m['btc_address']),
      btcUsdtPrice: _d(m['btc_usdt_price']),
    );
  }

  Future<Map<String, dynamic>> createOrder({
    required List<CartItem> cart,
    required PayMethod method,
    required String reference,
    required String name,
    required String phone,
    required String address,
    required String wallet,
  }) async {
    final j = await _rpc('create_order', {
      'p_lines': [
        for (final c in cart) {'product_id': c.product.id, 'qty': c.qty}
      ],
      'p_method': method.name,
      'p_reference': reference,
      'p_name': name,
      'p_phone': phone,
      'p_address': address,
      'p_wallet': wallet,
    });
    return Map<String, dynamic>.from(j as Map);
  }

  Future<List<Map<String, dynamic>>> myOrders(List<String> tokens) async {
    final j = await _rpc('my_orders', {'p_tokens': tokens});
    return (j as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ─────────── Sesión del vendedor ───────────

  Future<void> login(String email, String password) async {
    final r = await _guard(() => _c.post(
          Uri.parse('$kSupabaseUrl/auth/v1/token?grant_type=password'),
          headers: {'apikey': kSupabaseAnonKey, 'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim(), 'password': password}),
        ));
    if (r.statusCode != 200) {
      final msg = _errorMessage(r);
      if (msg.toLowerCase().contains('invalid')) {
        throw ApiException('Correo o contraseña incorrectos');
      }
      throw ApiException(msg);
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    _access = j['access_token'] as String?;
    _refresh = j['refresh_token'] as String?;
  }

  Future<void> _refreshSession() async {
    final token = _refresh;
    if (token == null) return;
    final r = await _guard(() => _c.post(
          Uri.parse('$kSupabaseUrl/auth/v1/token?grant_type=refresh_token'),
          headers: {'apikey': kSupabaseAnonKey, 'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': token}),
        ));
    if (r.statusCode != 200) {
      logout();
      throw ApiException('Tu sesión caducó. Vuelve a entrar.');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    _access = j['access_token'] as String?;
    _refresh = j['refresh_token'] as String?;
  }

  void logout() {
    _access = null;
    _refresh = null;
  }

  /// Precio actual en USD (≈ USDT) desde CoinGecko, para ayudar a fijar las tasas.
  Future<double> fetchUsdPrice(String coinId) async {
    final r = await _guard(() => _c.get(Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price?ids=$coinId&vs_currencies=usd')));
    if (r.statusCode != 200) {
      throw ApiException('No se pudo obtener el precio actual. Escríbelo a mano.');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final v = (j is Map && j[coinId] is Map) ? (j[coinId] as Map)['usd'] : null;
    final price = _d(v);
    if (price <= 0) throw ApiException('No se pudo obtener el precio actual. Escríbelo a mano.');
    return price;
  }

  // ─────────── Vendedor ───────────

  Future<List<OrderRecord>> adminOrders() async {
    final j = await _rpc('admin_orders');
    return (j as List)
        .map((e) => orderFromRow(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> adminSetStatus(String id, OrderStatus status, String note) =>
      _rpc('admin_set_order_status', {'p_id': id, 'p_status': status.name, 'p_note': note});

  Future<List<Product>> adminProducts() async {
    final j = await _rpc('admin_list_products');
    return (j as List).map((e) => productFromRow(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> adminSaveProduct(Product p) async {
    final isUuid = RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(p.id);
    await _rpc('admin_save_product', {
      'p': {
        'id': isUuid ? p.id : null,
        'name': p.name,
        'subtitle': p.subtitle,
        'description': p.description,
        'kind': p.kind.name,
        'price_cup': p.priceCUP,
        'price_mlc': p.priceMLC,
        'price_usdt': p.priceUSDT,
        'image_url': p.imageUrl,
        'download_url': p.downloadUrl,
        'is_digital': p.isDigital,
        'badge': p.badge,
        'featured': p.featured,
        'active': p.active,
      }
    });
  }

  Future<void> adminDeleteProduct(String id) => _rpc('admin_delete_product', {'p_id': id});

  Future<void> adminSaveSettings(StoreConfig c) => _rpc('admin_save_settings', {
        'p': {
          'business_name': c.businessName,
          'whatsapp': c.whatsapp,
          'cup_card': c.cupCard,
          'mlc_card': c.mlcCard,
          'tron_address': c.tronAddress,
          'trx_per_usdt': c.trxPerUsdt,
          'btc_address': c.btcAddress,
          'btc_usdt_price': c.btcUsdtPrice,
        }
      });

  /// Sube una foto al almacenamiento del servidor y devuelve su URL pública.
  Future<String> uploadImage(File file) async {
    final bytes = await file.readAsBytes();
    final lower = file.path.toLowerCase();
    final ext = lower.endsWith('.png') ? 'png' : (lower.endsWith('.webp') ? 'webp' : 'jpg');
    final mime = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
    final name = 'p_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _send(() => _c.post(
          _u('/storage/v1/object/product-images/$name'),
          headers: {
            'apikey': kSupabaseAnonKey,
            if (_access != null) 'Authorization': 'Bearer $_access',
            'Content-Type': mime,
          },
          body: bytes,
        ));
    return '$kSupabaseUrl/storage/v1/object/public/product-images/$name';
  }
}
DLJ_EOF_1
cat > 'lib/main.dart' <<'DLJ_EOF_2'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/shell.dart';
import 'state/app_store.dart';
import 'theme/app_theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const DljStoreApp());
}

class DljStoreApp extends StatefulWidget {
  const DljStoreApp({super.key});
  @override
  State<DljStoreApp> createState() => _DljStoreAppState();
}

class _DljStoreAppState extends State<DljStoreApp> {
  final AppStore store = AppStore();
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Future.wait([
      store.load(),
      Future.delayed(const Duration(milliseconds: 1600)),
    ]);
    if (mounted) setState(() => ready = true);
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      child: MaterialApp(
        title: 'HANDMADE D.L.J STORE',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: ready ? const MainShell(key: ValueKey('shell')) : const _Splash(key: ValueKey('splash')),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Palette.hero),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandLogo(size: 120),
                SizedBox(height: 26),
                Text('HANDMADE D.L.J',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3)),
                SizedBox(height: 6),
                Text('STORE',
                    style: TextStyle(
                        color: Palette.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
DLJ_EOF_2
cat > 'lib/models/models.dart' <<'DLJ_EOF_3'
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// ───────────────────────── Monedas ─────────────────────────

enum Cur { cup, mlc, usdt }

extension CurX on Cur {
  String get code => switch (this) {
        Cur.cup => 'CUP',
        Cur.mlc => 'MLC',
        Cur.usdt => 'USDT',
      };
  int get decimals => this == Cur.cup ? 0 : 2;
}

// ───────────────────────── Catálogo ─────────────────────────

enum ProductKind { app, game, art, painting, sculpture, craft }

extension ProductKindX on ProductKind {
  String get label => switch (this) {
        ProductKind.app => 'App',
        ProductKind.game => 'Juego',
        ProductKind.art => 'Arte',
        ProductKind.painting => 'Pintura',
        ProductKind.sculpture => 'Escultura',
        ProductKind.craft => 'Artesanía',
      };

  String get plural => switch (this) {
        ProductKind.app => 'Apps',
        ProductKind.game => 'Juegos',
        ProductKind.art => 'Arte',
        ProductKind.painting => 'Pinturas',
        ProductKind.sculpture => 'Esculturas',
        ProductKind.craft => 'Artesanías',
      };

  IconData get icon => switch (this) {
        ProductKind.app => Icons.phone_android_rounded,
        ProductKind.game => Icons.sports_esports_rounded,
        ProductKind.art => Icons.auto_awesome_rounded,
        ProductKind.painting => Icons.palette_rounded,
        ProductKind.sculpture => Icons.architecture_rounded,
        ProductKind.craft => Icons.handyman_rounded,
      };

  Color get accent => switch (this) {
        ProductKind.app => const Color(0xFF4F46E5),
        ProductKind.game => const Color(0xFFF59E0B),
        ProductKind.art => const Color(0xFF9333EA),
        ProductKind.painting => const Color(0xFFE5484D),
        ProductKind.sculpture => const Color(0xFF92400E),
        ProductKind.craft => const Color(0xFF0D9488),
      };

  bool get digitalByDefault => this == ProductKind.app || this == ProductKind.game;
}

class Product {
  final String id;
  final String name;
  final String subtitle;
  final String description;
  final ProductKind kind;
  final double priceCUP;
  final double priceMLC;
  final double priceUSDT;
  final String imageUrl;
  final String imagePath;
  final String downloadUrl;
  final bool isDigital;
  final String badge;
  final bool featured;
  final bool active;

  const Product({
    required this.id,
    required this.name,
    this.subtitle = '',
    this.description = '',
    required this.kind,
    required this.priceCUP,
    required this.priceMLC,
    required this.priceUSDT,
    this.imageUrl = '',
    this.imagePath = '',
    this.downloadUrl = '',
    required this.isDigital,
    this.badge = '',
    this.featured = false,
    this.active = true,
  });

  double priceIn(Cur c) => switch (c) {
        Cur.cup => priceCUP,
        Cur.mlc => priceMLC,
        Cur.usdt => priceUSDT,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subtitle': subtitle,
        'description': description,
        'kind': kind.name,
        'priceCUP': priceCUP,
        'priceMLC': priceMLC,
        'priceUSDT': priceUSDT,
        'imageUrl': imageUrl,
        'imagePath': imagePath,
        'downloadUrl': downloadUrl,
        'isDigital': isDigital,
        'badge': badge,
        'featured': featured,
        'active': active,
      };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        subtitle: (j['subtitle'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        kind: ProductKind.values.firstWhere(
          (e) => e.name == j['kind'],
          orElse: () => ProductKind.app,
        ),
        priceCUP: (j['priceCUP'] as num?)?.toDouble() ?? 0,
        priceMLC: (j['priceMLC'] as num?)?.toDouble() ?? 0,
        priceUSDT: (j['priceUSDT'] as num?)?.toDouble() ?? 0,
        imageUrl: (j['imageUrl'] as String?) ?? '',
        imagePath: (j['imagePath'] as String?) ?? '',
        downloadUrl: (j['downloadUrl'] as String?) ?? '',
        isDigital: (j['isDigital'] as bool?) ?? true,
        badge: (j['badge'] as String?) ?? '',
        featured: (j['featured'] as bool?) ?? false,
        active: (j['active'] as bool?) ?? true,
      );
}

class CartItem {
  final Product product;
  int qty;
  CartItem(this.product, [this.qty = 1]);
}

// ───────────────────────── Configuración del vendedor ─────────────────────────

class StoreConfig {
  String businessName;
  String whatsapp; // solo dígitos con código de país, p. ej. 5351234567
  String cupCard;
  String mlcCard;
  String tronAddress;
  double trxPerUsdt; // 0 = TRX desactivado
  String btcAddress;
  double btcUsdtPrice; // USDT por 1 BTC; 0 = Bitcoin desactivado
  String pinHash;
  String pinSalt;

  StoreConfig({
    this.businessName = 'HANDMADE D.L.J STORE',
    this.whatsapp = '',
    this.cupCard = '',
    this.mlcCard = '',
    this.tronAddress = '',
    this.trxPerUsdt = 0,
    this.btcAddress = '',
    this.btcUsdtPrice = 0,
    this.pinHash = '',
    this.pinSalt = '',
  });

  bool get hasCup => cupCard.trim().isNotEmpty;
  bool get hasMlc => mlcCard.trim().isNotEmpty;
  bool get hasTron => tronAddress.trim().isNotEmpty;
  bool get hasTrx => hasTron && trxPerUsdt > 0;
  bool get hasBtc => btcAddress.trim().isNotEmpty && btcUsdtPrice > 0;
  bool get hasWhatsapp => whatsapp.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'whatsapp': whatsapp,
        'cupCard': cupCard,
        'mlcCard': mlcCard,
        'tronAddress': tronAddress,
        'trxPerUsdt': trxPerUsdt,
        'btcAddress': btcAddress,
        'btcUsdtPrice': btcUsdtPrice,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
      };

  factory StoreConfig.fromJson(Map<String, dynamic> j) => StoreConfig(
        businessName: (j['businessName'] as String?) ?? 'HANDMADE D.L.J STORE',
        whatsapp: (j['whatsapp'] as String?) ?? '',
        cupCard: (j['cupCard'] as String?) ?? '',
        mlcCard: (j['mlcCard'] as String?) ?? '',
        tronAddress: (j['tronAddress'] as String?) ?? '',
        trxPerUsdt: (j['trxPerUsdt'] as num?)?.toDouble() ?? 0,
        btcAddress: (j['btcAddress'] as String?) ?? '',
        btcUsdtPrice: (j['btcUsdtPrice'] as num?)?.toDouble() ?? 0,
        pinHash: (j['pinHash'] as String?) ?? '',
        pinSalt: (j['pinSalt'] as String?) ?? '',
      );
}

// ───────────────────────── Cliente ─────────────────────────

class CustomerProfile {
  String name;
  String phone;
  String address;
  String wallet; // dirección TRON vinculada (T...)

  CustomerProfile({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.wallet = '',
  });

  bool get hasWallet => wallet.trim().isNotEmpty;

  Map<String, dynamic> toJson() =>
      {'name': name, 'phone': phone, 'address': address, 'wallet': wallet};

  factory CustomerProfile.fromJson(Map<String, dynamic> j) => CustomerProfile(
        name: (j['name'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
        wallet: (j['wallet'] as String?) ?? '',
      );
}

// ───────────────────────── Pedidos ─────────────────────────

enum PayMethod { transfermovilCup, transfermovilMlc, usdtTrc20, trx, btc }

extension PayMethodX on PayMethod {
  String get label => switch (this) {
        PayMethod.transfermovilCup => 'Transfermóvil CUP',
        PayMethod.transfermovilMlc => 'Transfermóvil MLC',
        PayMethod.usdtTrc20 => 'USDT · TRC20',
        PayMethod.trx => 'TRX · TRON',
        PayMethod.btc => 'Bitcoin · BTC',
      };

  String get currencyCode => switch (this) {
        PayMethod.transfermovilCup => 'CUP',
        PayMethod.transfermovilMlc => 'MLC',
        PayMethod.usdtTrc20 => 'USDT',
        PayMethod.trx => 'TRX',
        PayMethod.btc => 'BTC',
      };

  bool get isCrypto =>
      this == PayMethod.usdtTrc20 || this == PayMethod.trx || this == PayMethod.btc;

  int get decimals => switch (this) {
        PayMethod.transfermovilCup => 0,
        PayMethod.btc => 8,
        _ => 2,
      };
}

enum OrderStatus { pending, verified, rejected, delivered }

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pending => 'Pendiente de verificación',
        OrderStatus.verified => 'Pago verificado',
        OrderStatus.rejected => 'Pago rechazado',
        OrderStatus.delivered => 'Entregado',
      };

  Color get color => switch (this) {
        OrderStatus.pending => Palette.warn,
        OrderStatus.verified => Palette.ok,
        OrderStatus.rejected => Palette.danger,
        OrderStatus.delivered => const Color(0xFF2563EB),
      };

  IconData get icon => switch (this) {
        OrderStatus.pending => Icons.hourglass_top_rounded,
        OrderStatus.verified => Icons.verified_rounded,
        OrderStatus.rejected => Icons.cancel_rounded,
        OrderStatus.delivered => Icons.local_shipping_rounded,
      };

  /// Los enlaces de descarga solo se liberan con el pago confirmado.
  bool get unlocksDownloads =>
      this == OrderStatus.verified || this == OrderStatus.delivered;
}

class OrderLine {
  final String productId;
  final String name;
  final ProductKind kind;
  final int qty;
  final double unitCUP;
  final double unitMLC;
  final double unitUSDT;
  final bool isDigital;
  final String downloadUrl;

  const OrderLine({
    required this.productId,
    required this.name,
    required this.kind,
    required this.qty,
    required this.unitCUP,
    required this.unitMLC,
    required this.unitUSDT,
    required this.isDigital,
    required this.downloadUrl,
  });

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'kind': kind.name,
        'qty': qty,
        'unitCUP': unitCUP,
        'unitMLC': unitMLC,
        'unitUSDT': unitUSDT,
        'isDigital': isDigital,
        'downloadUrl': downloadUrl,
      };

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        productId: (j['productId'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        kind: ProductKind.values.firstWhere(
          (e) => e.name == j['kind'],
          orElse: () => ProductKind.app,
        ),
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        unitCUP: (j['unitCUP'] as num?)?.toDouble() ?? 0,
        unitMLC: (j['unitMLC'] as num?)?.toDouble() ?? 0,
        unitUSDT: (j['unitUSDT'] as num?)?.toDouble() ?? 0,
        isDigital: (j['isDigital'] as bool?) ?? true,
        downloadUrl: (j['downloadUrl'] as String?) ?? '',
      );
}

class OrderRecord {
  final String id;
  final String code;
  final String accessToken; // clave secreta del pedido (modo servidor)
  final List<OrderLine> lines;
  final PayMethod method;
  final double amount; // monto en la moneda del método de pago
  final String reference; // nº de transacción Transfermóvil o TXID
  final String customerName;
  final String phone;
  final String address;
  final String fromWallet;
  final DateTime createdAt;
  OrderStatus status;
  String sellerNote;

  OrderRecord({
    required this.id,
    required this.code,
    this.accessToken = '',
    required this.lines,
    required this.method,
    required this.amount,
    required this.reference,
    required this.customerName,
    required this.phone,
    this.address = '',
    this.fromWallet = '',
    required this.createdAt,
    this.status = OrderStatus.pending,
    this.sellerNote = '',
  });

  bool get hasPhysical => lines.any((l) => !l.isDigital);
  bool get hasDigital => lines.any((l) => l.isDigital && l.downloadUrl.isNotEmpty);
  double get totalCUP => lines.fold(0.0, (s, l) => s + l.unitCUP * l.qty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'accessToken': accessToken,
        'lines': lines.map((e) => e.toJson()).toList(),
        'method': method.name,
        'amount': amount,
        'reference': reference,
        'customerName': customerName,
        'phone': phone,
        'address': address,
        'fromWallet': fromWallet,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'sellerNote': sellerNote,
      };

  factory OrderRecord.fromJson(Map<String, dynamic> j) => OrderRecord(
        id: j['id'] as String,
        code: (j['code'] as String?) ?? (j['id'] as String),
        accessToken: (j['accessToken'] as String?) ?? '',
        lines: ((j['lines'] as List?) ?? [])
            .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        method: PayMethod.values.firstWhere(
          (e) => e.name == j['method'],
          orElse: () => PayMethod.transfermovilCup,
        ),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        reference: (j['reference'] as String?) ?? '',
        customerName: (j['customerName'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
        address: (j['address'] as String?) ?? '',
        fromWallet: (j['fromWallet'] as String?) ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
        status: OrderStatus.values.firstWhere(
          (e) => e.name == j['status'],
          orElse: () => OrderStatus.pending,
        ),
        sellerNote: (j['sellerNote'] as String?) ?? '',
      );
}
DLJ_EOF_3
cat > 'lib/screens/account_page.dart' <<'DLJ_EOF_4'
import 'package:flutter/material.dart';

import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';
import 'seller_pages.dart';
import 'wallet_page.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final p = store.profile;
    final name = p.name.trim().isEmpty ? 'Invitado' : p.name.trim();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: Palette.hero,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
          ),
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 28),
          child: Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Palette.coral,
                child: Text(name.characters.first.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(p.phone.isEmpty ? 'Completa tu perfil para comprar más rápido' : p.phone,
                        style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Mi cuenta'),
        _Tile(
          icon: Icons.person_rounded,
          title: 'Mis datos',
          subtitle: 'Nombre, teléfono y dirección de entrega',
          onTap: () => _editProfile(context, store),
        ),
        _Tile(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Mi wallet',
          subtitle: p.hasWallet ? 'Vinculada · ${shortAddress(p.wallet)}' : 'Vincula tu wallet TRON para pagar en crypto',
          trailing: p.hasWallet ? const Icon(Icons.verified_rounded, color: Palette.ok) : null,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletPage())),
        ),
        _Tile(
          icon: Icons.payments_rounded,
          title: 'Moneda de los precios',
          subtitle: 'Se aplica en toda la tienda',
          below: CurrencySwitch(value: store.currency, onChanged: store.setCurrency),
        ),
        const SectionTitle('Ajustes'),
        _Tile(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Acceso de vendedor',
          subtitle: store.pendingCount > 0
              ? '${store.pendingCount} pedido(s) por verificar'
              : 'Catálogo, pedidos, tarjetas de cobro y wallets',
          trailing: store.pendingCount > 0
              ? Badge(label: Text('${store.pendingCount}'))
              : const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SellerGate())),
        ),
        const SectionTitle('Información'),
        _Tile(
          icon: Icons.info_rounded,
          title: 'HANDMADE D.L.J STORE',
          subtitle: 'Versión 2.2 · Apps, juegos, arte, pintura, escultura y artesanías',
          trailing: const SizedBox.shrink(),
          onTap: () async {
            final revealed = await store.aboutTap();
            if (revealed && context.mounted) toast(context, 'Modo vendedor activado');
          },
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  void _editProfile(BuildContext context, AppStore store) {
    final name = TextEditingController(text: store.profile.name);
    final phone = TextEditingController(text: store.profile.phone);
    final address = TextEditingController(text: store.profile.address);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(22, 22, 22, MediaQuery.of(ctx).viewInsets.bottom + 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Mis datos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: name, decoration: fieldDec('Nombre', icon: Icons.person_outline_rounded)),
            const SizedBox(height: 12),
            TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: fieldDec('Teléfono / WhatsApp', icon: Icons.phone_outlined)),
            const SizedBox(height: 12),
            TextField(
                controller: address,
                maxLines: 2,
                decoration: fieldDec('Dirección de entrega', icon: Icons.location_on_outlined)),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () async {
                store.profile
                  ..name = name.text.trim()
                  ..phone = phone.text.trim()
                  ..address = address.text.trim();
                await store.saveProfile();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: SoftCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Palette.navy.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Palette.navy),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.3)),
                  if (below != null) ...[const SizedBox(height: 10), below!],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!]
            else if (onTap != null) const Icon(Icons.chevron_right_rounded, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}
DLJ_EOF_4
cat > 'lib/screens/cart_page.dart' <<'DLJ_EOF_5'
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';
import 'checkout_page.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final cur = store.currency;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi carrito'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: CurrencySwitch(value: cur, onChanged: store.setCurrency)),
          ),
        ],
      ),
      body: store.cart.isEmpty
          ? const EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Tu carrito está vacío',
              message: 'Explora la tienda y añade apps, juegos o piezas de arte.',
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    itemCount: store.cart.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _CartRow(item: store.cart[i], store: store),
                  ),
                ),
                _Summary(store: store),
              ],
            ),
    );
  }
}

class _CartRow extends StatelessWidget {
  final CartItem item;
  final AppStore store;
  const _CartRow({required this.item, required this.store});

  @override
  Widget build(BuildContext context) {
    final p = item.product;
    final cur = store.currency;
    return Dismissible(
      key: ValueKey('cart-${p.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => store.removeFromCart(item),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Palette.danger,
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: SoftCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(width: 78, height: 78, child: ProductImage(product: p, height: 78)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(p.isDigital ? 'Entrega digital' : 'Envío físico',
                      style: const TextStyle(color: Palette.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(money(p.priceIn(cur) * item.qty, cur),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Palette.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _QtyButton(icon: Icons.add_rounded, onTap: () => store.changeQty(item, 1)),
                  Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  _QtyButton(icon: Icons.remove_rounded, onTap: () => store.changeQty(item, -1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 18)),
      );
}

class _Summary extends StatelessWidget {
  final AppStore store;
  const _Summary({required this.store});

  @override
  Widget build(BuildContext context) {
    final cur = store.currency;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Palette.navy.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, -8)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('Total', style: TextStyle(color: Palette.muted, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(money(store.cartTotal(cur), cur),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                [
                  for (final c in Cur.values.where((c) => c != cur)) money(store.cartTotal(c), c),
                ].join('  ·  '),
                style: const TextStyle(color: Palette.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            CoralButton(
              label: 'Continuar al pago',
              icon: Icons.lock_rounded,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CheckoutPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
DLJ_EOF_5
cat > 'lib/screens/checkout_page.dart' <<'DLJ_EOF_6'
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';
import 'payment_crypto_page.dart';
import 'payment_transfermovil_page.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _form = GlobalKey<FormState>();
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  PayMethod? method;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final st = AppScope.of(context);
    if (st.remote) {
      WidgetsBinding.instance.addPostFrameCallback((_) => st.refreshRemote());
    }
    final prof = st.profile;
    name.text = prof.name;
    phone.text = prof.phone;
    address.text = prof.address;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    address.dispose();
    super.dispose();
  }

  bool _available(AppStore s, PayMethod m) => switch (m) {
        PayMethod.transfermovilCup => s.cfg.hasCup,
        PayMethod.transfermovilMlc => s.cfg.hasMlc,
        PayMethod.usdtTrc20 => s.cfg.hasTron,
        PayMethod.trx => s.cfg.hasTrx,
        PayMethod.btc => s.cfg.hasBtc,
      };

  void _continue(AppStore store) {
    if (!_form.currentState!.validate()) return;
    if (method == null) {
      toast(context, 'Elige un método de pago');
      return;
    }
    final data = CheckoutData(
      name: name.text,
      phone: phone.text,
      address: store.cartHasPhysical ? address.text : '',
    );
    final page = method!.isCrypto
        ? PaymentCryptoPage(method: method!, data: data)
        : PaymentTransfermovilPage(method: method!, data: data);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final physical = store.cartHasPhysical;

    return Scaffold(
      appBar: AppBar(title: const Text('Finalizar compra')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            const _StepLabel(n: '1', text: 'Tus datos'),
            const SizedBox(height: 12),
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: fieldDec('Nombre completo', icon: Icons.person_outline_rounded),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Escribe tu nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: fieldDec('Teléfono / WhatsApp', icon: Icons.phone_outlined),
              validator: (v) => onlyDigits(v ?? '').length < 8 ? 'Teléfono no válido' : null,
            ),
            if (physical) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: address,
                maxLines: 2,
                decoration: fieldDec('Dirección de entrega',
                    hint: 'Provincia, municipio, calle y número', icon: Icons.location_on_outlined),
                validator: (v) => (v == null || v.trim().length < 8) ? 'Escribe la dirección de entrega' : null,
              ),
            ],
            const SizedBox(height: 28),
            const _StepLabel(n: '2', text: 'Método de pago'),
            const SizedBox(height: 12),
            for (final m in PayMethod.values) ...[
              if ((m != PayMethod.trx || store.cfg.hasTrx) &&
                  (m != PayMethod.btc || store.cfg.hasBtc))
                _MethodTile(
                  method: m,
                  amount: store.amountFor(m),
                  available: _available(store, m),
                  selected: method == m,
                  onTap: () => setState(() => method = m),
                ),
            ],
            const SizedBox(height: 22),
            SoftCard(
              child: Row(
                children: [
                  const Text('Total a pagar',
                      style: TextStyle(color: Palette.muted, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                    method == null
                        ? '—'
                        : '${moneyPlain(store.amountFor(method!), method!.decimals)} ${method!.currencyCode}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CoralButton(
              label: 'Continuar',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => _continue(store),
            ),
          ],
        ),
      ),
    );
  }
}

class CheckoutData {
  final String name;
  final String phone;
  final String address;
  const CheckoutData({required this.name, required this.phone, required this.address});
}

class _StepLabel extends StatelessWidget {
  final String n;
  final String text;
  const _StepLabel({required this.n, required this.text});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Palette.navy, shape: BoxShape.circle),
            child: Text(n,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      );
}

class _MethodTile extends StatelessWidget {
  final PayMethod method;
  final double amount;
  final bool available;
  final bool selected;
  final VoidCallback onTap;
  const _MethodTile({
    required this.method,
    required this.amount,
    required this.available,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = method.isCrypto ? Icons.account_balance_wallet_rounded : Icons.credit_card_rounded;
    final subtitle = !available
        ? 'No disponible por ahora'
        : method.isCrypto
            ? (method == PayMethod.btc
                ? 'Red Bitcoin · confirmación en blockchain'
                : 'Red TRON · confirmación en blockchain')
            : 'Transferencia desde Transfermóvil';
    final decimals = method.decimals;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: available ? 1 : 0.5,
        child: GestureDetector(
          onTap: available ? onTap : () => toast(context, 'El vendedor aún no configuró este método'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? Palette.coral : Palette.line,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected ? softShadow(0.1) : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: (method.isCrypto ? Palette.coral : Palette.navy).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: method.isCrypto ? Palette.coralDeep : Palette.navy),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (available)
                  Text('${moneyPlain(amount, decimals)} ${method.currencyCode}',
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 6),
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? Palette.coral : Palette.line,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
DLJ_EOF_6
cat > 'lib/screens/home_page.dart' <<'DLJ_EOF_7'
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';
import 'product_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  ProductKind? kind;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final q = query.trim().toLowerCase();
    final filtered = store.products.where((p) {
      if (kind != null && p.kind != kind) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.subtitle.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
    }).toList();
    final featured = store.products.where((p) => p.featured).toList();
    final showFeatured = q.isEmpty && kind == null && featured.isNotEmpty;

    return RefreshIndicator(
      color: Palette.coral,
      onRefresh: store.refreshRemote,
      child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _Header(
          store: store,
          onQuery: (v) => setState(() => query = v),
        )),
        SliverToBoxAdapter(child: _Categories(
          selected: kind,
          onSelect: (k) => setState(() => kind = k),
        )),
        if (showFeatured) ...[
          const SliverToBoxAdapter(child: _PromoBanner()),
          const SliverToBoxAdapter(child: SectionTitle('Destacados')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 262,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: featured.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => SizedBox(
                  width: 168,
                  child: ProductCard(product: featured[i], heroScope: 'feat'),
                ),
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: SectionTitle(kind == null ? 'Todo el catálogo' : kind!.plural),
        ),
        if (filtered.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 30, bottom: 60),
              child: EmptyState(
                icon: store.products.isEmpty ? Icons.cloud_off_rounded : Icons.search_off_rounded,
                title: store.products.isEmpty
                    ? (store.syncError != null ? 'No pudimos cargar la tienda' : 'Pronto habrá productos')
                    : 'Sin resultados',
                message: store.products.isEmpty
                    ? (store.syncError ?? 'Estamos preparando el catálogo. Vuelve en un momento.')
                    : 'Prueba con otra palabra o elige otra categoría.',
                action: store.products.isEmpty && store.remote
                    ? SizedBox(
                        width: 200,
                        child: OutlinedButton(
                          onPressed: store.refreshRemote,
                          child: const Text('Reintentar'),
                        ),
                      )
                    : null,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.68,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => ProductCard(product: filtered[i]),
                childCount: filtered.length,
              ),
            ),
          ),
      ],
    ),
    );
  }
}

class _Header extends StatelessWidget {
  final AppStore store;
  final ValueChanged<String> onQuery;
  const _Header({required this.store, required this.onQuery});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: Palette.hero,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandLogo(size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(store.cfg.businessName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4)),
                    const Text('Apps · Arte · Artesanías',
                        style: TextStyle(color: Palette.gold, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const Text('Descubre piezas\ncon identidad propia',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6)),
          const SizedBox(height: 18),
          TextField(
            onChanged: onQuery,
            style: const TextStyle(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Buscar apps, cuadros, lámparas…',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('Ver precios en',
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const Spacer(),
              CurrencySwitch(value: store.currency, onChanged: store.setCurrency, dark: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _Categories extends StatelessWidget {
  final ProductKind? selected;
  final ValueChanged<ProductKind?> onSelect;
  const _Categories({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, IconData icon, bool sel, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: sel ? Palette.navy : Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: sel ? null : softShadow(0.05),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: sel ? Colors.white : Palette.navy),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : Palette.ink)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        children: [
          chip('Todo', Icons.grid_view_rounded, selected == null, () => onSelect(null)),
          for (final k in ProductKind.values) ...[
            const SizedBox(width: 10),
            chip(k.plural, k.icon, selected == k, () => onSelect(selected == k ? null : k)),
          ],
        ],
      ),
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF1F1), Color(0xFFFFE0E0)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Palette.coral.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Paga como te convenga',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text(
                    'Transfermóvil en CUP o MLC, o criptomonedas en red TRON.',
                    style: TextStyle(color: Palette.muted, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: const [
                      Pill('CUP', icon: Icons.credit_card_rounded),
                      Pill('MLC', icon: Icons.credit_card_rounded),
                      Pill('USDT', icon: Icons.account_balance_wallet_rounded, color: Palette.coralDeep),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.verified_user_rounded, size: 54, color: Palette.coral.withOpacity(0.85)),
          ],
        ),
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final Product product;
  final String heroScope;
  const ProductCard({super.key, required this.product, this.heroScope = 'grid'});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final p = product;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => ProductPage(product: p, heroTag: '$heroScope-${p.id}')),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: softShadow(),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(tag: '$heroScope-${p.id}', child: ProductImage(product: p)),
                  if (p.badge.isNotEmpty)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(p.badge,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800, color: Palette.navy)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text(p.kind.label,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: p.kind.accent)),
                        const SizedBox(height: 6),
                        Text(money(p.priceIn(store.currency), store.currency),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      store.addToCart(p);
                      toast(context, '${p.name} añadido al carrito');
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: Palette.coralGradient,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.add_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
DLJ_EOF_7
cat > 'lib/screens/order_success_page.dart' <<'DLJ_EOF_8'
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';

/// Texto del comprobante que el cliente envía al vendedor por WhatsApp.
String orderMessage(OrderRecord o) {
  final items = o.lines.map((l) => '• ${l.name} ×${l.qty}').join('\n');
  final amount = '${moneyPlain(o.amount, o.method.decimals)} ${o.method.currencyCode}';
  final refLabel = o.method.isCrypto ? 'TXID' : 'Nº transacción';
  return 'Hola, acabo de pagar mi pedido ${o.code}.\n\n$items\n\n'
      'Método: ${o.method.label}\nMonto: $amount\n$refLabel: ${o.reference}\n'
      'Nombre: ${o.customerName}\nTeléfono: ${o.phone}'
      '${o.address.isEmpty ? '' : '\nDirección: ${o.address}'}';
}

class OrderSuccessPage extends StatelessWidget {
  final OrderRecord order;
  const OrderSuccessPage({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final wa = onlyDigits(store.cfg.whatsapp);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
          children: [
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (_, t, child) => Transform.scale(scale: t, child: child),
                child: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    gradient: Palette.coralGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Palette.coral.withOpacity(0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 14)),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 58),
                ),
              ),
            ),
            const SizedBox(height: 26),
            const Text('¡Pedido recibido!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
            const SizedBox(height: 8),
            const Text(
              'Verificaremos tu pago y te avisaremos. Tu compra se libera en cuanto quede confirmado.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.muted, height: 1.4),
            ),
            const SizedBox(height: 24),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Estado', style: TextStyle(color: Palette.muted, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      StatusChip(order.status),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CopyRow(label: 'Código de pedido', value: order.code),
                  const SizedBox(height: 10),
                  CopyRow(label: order.method.isCrypto ? 'TXID' : 'Nº de transacción', value: order.reference),
                ],
              ),
            ),
            const SizedBox(height: 22),
            if (wa.isNotEmpty) ...[
              CoralButton(
                label: 'Enviar comprobante por WhatsApp',
                icon: Icons.send_rounded,
                onPressed: () async {
                  final url = 'https://wa.me/$wa?text=${Uri.encodeComponent(orderMessage(order))}';
                  final ok = await openUrl(url);
                  if (!ok && context.mounted) toast(context, 'No se pudo abrir WhatsApp');
                },
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: () => copyText(context, orderMessage(order), 'Resumen del pedido'),
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              label: const Text('Copiar resumen del pedido'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('Volver a la tienda'),
            ),
          ],
        ),
      ),
    );
  }
}
DLJ_EOF_8
cat > 'lib/screens/payment_crypto_page.dart' <<'DLJ_EOF_9'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/api.dart';
import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';
import 'checkout_page.dart';
import 'order_success_page.dart';
import 'wallet_page.dart';

class PaymentCryptoPage extends StatefulWidget {
  final PayMethod method;
  final CheckoutData data;
  const PaymentCryptoPage({super.key, required this.method, required this.data});
  @override
  State<PaymentCryptoPage> createState() => _PaymentCryptoPageState();
}

class _PaymentCryptoPageState extends State<PaymentCryptoPage> {
  final _form = GlobalKey<FormState>();
  final txid = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    txid.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isEmpty) {
      if (mounted) toast(context, 'El portapapeles está vacío');
      return;
    }
    setState(() => txid.text = t);
  }

  Future<void> _openWallet(String uri) async {
    final ok = await openUrl(uri);
    if (!ok && mounted) {
      toast(context, 'No se encontró una wallet compatible. Copia la dirección y pégala en tu wallet.');
    }
  }

  Future<void> _submit(AppStore store) async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final order = await store.createOrder(
        method: widget.method,
        reference: txid.text,
        name: widget.data.name,
        phone: widget.data.phone,
        address: widget.data.address,
        fromWallet: widget.method == PayMethod.btc ? '' : store.profile.wallet,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => OrderSuccessPage(order: order)),
        (r) => r.isFirst,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final m = widget.method;
    final isBtc = m == PayMethod.btc;
    final address = (isBtc ? store.cfg.btcAddress : store.cfg.tronAddress).trim();
    final amount = store.amountFor(m);
    final isTrx = m == PayMethod.trx;
    final asset = isBtc ? 'BTC' : (isTrx ? 'TRX' : 'USDT');
    final amountText = amount.toStringAsFixed(m.decimals);
    final walletUri = isBtc ? 'bitcoin:$address?amount=$amountText' : 'tron:$address';

    return Scaffold(
      appBar: AppBar(title: Text('Pagar con $asset')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: Palette.hero,
                borderRadius: BorderRadius.circular(26),
                boxShadow: softShadow(0.25),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Pill(isBtc ? 'Red Bitcoin' : 'Red TRON · TRC20', icon: Icons.hub_rounded, color: Palette.gold),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Envía exactamente',
                      style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text('$amountText $asset',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.8)),
                      ),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.15)),
                        onPressed: () => copyText(context, amountText, 'Monto'),
                        icon: const Icon(Icons.copy_rounded, size: 20, color: Colors.white),
                      ),
                    ],
                  ),
                  if (isTrx) ...[
                    const SizedBox(height: 4),
                    Text('Tasa fijada por la tienda: 1 USDT = ${store.cfg.trxPerUsdt} TRX',
                        style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                  ],
                  if (isBtc) ...[
                    const SizedBox(height: 4),
                    Text('Tasa fijada por la tienda: 1 BTC = ${store.cfg.btcUsdtPrice} USDT',
                        style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Palette.warn.withOpacity(0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Palette.warn),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isBtc
                          ? 'Envía solo Bitcoin (BTC) por la red Bitcoin. Otro activo u otra red puede perder los fondos para siempre.'
                          : (isTrx
                              ? 'Envía solo TRX por la red TRON. Otro activo u otra red puede perder los fondos para siempre.'
                              : 'Envía solo USDT por la red TRON (TRC20). Si usas otra red (ERC20, BEP20…) perderás los fondos.'),
                      style: const TextStyle(height: 1.35, fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SoftCard(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Palette.line),
                    ),
                    child: QrImageView(
                      data: isBtc ? walletUri : address,
                      size: 190,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Palette.navy),
                      dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square, color: Palette.navy),
                    ),
                  ),
                  const SizedBox(height: 14),
                  CopyRow(label: 'Dirección de la tienda', value: address, display: address),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _openWallet(walletUri),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Abrir mi wallet'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!isBtc) ...[
              _WalletBox(store: store, onChanged: () => setState(() {})),
              const SizedBox(height: 18),
            ],
            TextFormField(
              controller: txid,
              minLines: 1,
              maxLines: 3,
              decoration: fieldDec('TXID de la transacción',
                      hint: '64 caracteres hexadecimales', icon: Icons.tag_rounded)
                  .copyWith(
                suffixIcon: IconButton(
                  tooltip: 'Pegar',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: _paste,
                ),
              ),
              validator: (v) => isValidTxId(v ?? '')
                  ? null
                  : 'El TXID debe tener 64 caracteres hexadecimales (0-9, a-f)',
            ),
            const SizedBox(height: 8),
            const Text(
              'Lo encuentras en tu wallet, en el detalle de la transferencia enviada. '
              'Lo usamos para comprobar el pago en la blockchain.',
              style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 18),
            CoralButton(
              label: busy ? 'Enviando…' : 'Ya envié · Verificar pago',
              icon: Icons.verified_user_rounded,
              onPressed: busy ? null : () => _submit(store),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletBox extends StatelessWidget {
  final AppStore store;
  final VoidCallback onChanged;
  const _WalletBox({required this.store, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final linked = store.profile.hasWallet;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: linked ? Palette.ok.withOpacity(0.5) : Palette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (linked ? Palette.ok : Palette.navy).withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              linked ? Icons.link_rounded : Icons.link_off_rounded,
              color: linked ? Palette.ok : Palette.navy,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(linked ? 'Wallet vinculada' : 'Vincula tu wallet',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  linked
                      ? shortAddress(store.profile.wallet)
                      : 'Opcional: ayuda a identificar tu pago más rápido.',
                  style: const TextStyle(color: Palette.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WalletPage()),
              );
              onChanged();
            },
            child: Text(linked ? 'Cambiar' : 'Vincular'),
          ),
        ],
      ),
    );
  }
}
DLJ_EOF_9
cat > 'lib/screens/payment_transfermovil_page.dart' <<'DLJ_EOF_10'
import 'package:flutter/material.dart';

import '../data/api.dart';
import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';
import 'checkout_page.dart';
import 'order_success_page.dart';

class PaymentTransfermovilPage extends StatefulWidget {
  final PayMethod method;
  final CheckoutData data;
  const PaymentTransfermovilPage({super.key, required this.method, required this.data});
  @override
  State<PaymentTransfermovilPage> createState() => _PaymentTransfermovilPageState();
}

class _PaymentTransfermovilPageState extends State<PaymentTransfermovilPage> {
  final _form = GlobalKey<FormState>();
  final ref = TextEditingController();
  bool confirmed = false;
  bool busy = false;

  @override
  void dispose() {
    ref.dispose();
    super.dispose();
  }

  Future<void> _submit(AppStore store) async {
    if (!_form.currentState!.validate()) return;
    if (!confirmed) {
      toast(context, 'Confirma que hiciste la transferencia por el monto exacto');
      return;
    }
    setState(() => busy = true);
    try {
      final order = await store.createOrder(
        method: widget.method,
        reference: ref.text,
        name: widget.data.name,
        phone: widget.data.phone,
        address: widget.data.address,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => OrderSuccessPage(order: order)),
        (r) => r.isFirst,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final m = widget.method;
    final isCup = m == PayMethod.transfermovilCup;
    final card = isCup ? store.cfg.cupCard : store.cfg.mlcCard;
    final amount = store.amountFor(m);
    final amountText = moneyPlain(amount, m.decimals);

    return Scaffold(
      appBar: AppBar(title: Text(m.label)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            _BankCard(
              holder: store.cfg.businessName,
              number: formatCard(card),
              currency: m.currencyCode,
            ),
            const SizedBox(height: 18),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Monto exacto a transferir',
                      style: TextStyle(color: Palette.muted, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text('$amountText ${m.currencyCode}',
                            style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => copyText(context, amount.toStringAsFixed(m.decimals), 'Monto'),
                        icon: const Icon(Icons.copy_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CopyRow(
                    label: 'Tarjeta destino',
                    value: onlyDigits(card),
                    display: formatCard(card),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text('Cómo pagar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const _Step(n: 1, text: 'Abre Transfermóvil y elige «Transferir».'),
            const _Step(n: 2, text: 'Pega la tarjeta destino y envía el monto exacto.'),
            const _Step(n: 3, text: 'Copia el número de transacción del SMS o comprobante.'),
            const _Step(n: 4, text: 'Pégalo aquí abajo y confirma. Verificaremos tu pago.'),
            const SizedBox(height: 18),
            TextFormField(
              controller: ref,
              keyboardType: TextInputType.text,
              decoration: fieldDec('Nº de transacción de Transfermóvil',
                  hint: 'Ej. 1234567890', icon: Icons.tag_rounded),
              validator: (v) => (v == null || v.trim().length < 6)
                  ? 'Escribe el número de transacción (mínimo 6 caracteres)'
                  : null,
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: confirmed,
              onChanged: (v) => setState(() => confirmed = v ?? false),
              title: const Text('Transferí el monto exacto a la tarjeta indicada',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
            const SizedBox(height: 12),
            CoralButton(
              label: busy ? 'Enviando…' : 'Ya pagué · Enviar a verificación',
              icon: Icons.verified_user_rounded,
              onPressed: busy ? null : () => _submit(store),
            ),
          ],
        ),
      ),
    );
  }
}

class _BankCard extends StatelessWidget {
  final String holder;
  final String number;
  final String currency;
  const _BankCard({required this.holder, required this.number, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: Palette.hero,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: Palette.navy.withOpacity(0.35), blurRadius: 26, offset: const Offset(0, 14)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -50,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Palette.coral.withOpacity(0.18),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 30,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: const LinearGradient(colors: [Palette.gold, Color(0xFFB8914A)]),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(currency,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(number,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace')),
              ),
              const SizedBox(height: 14),
              const Text('TITULAR / DESTINO',
                  style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.6)),
              const SizedBox(height: 2),
              Text(holder.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Palette.coral.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: const TextStyle(
                    color: Palette.coralDeep, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(text, style: const TextStyle(height: 1.35, fontSize: 14.5)),
            ),
          ),
        ],
      ),
    );
  }
}
DLJ_EOF_10
cat > 'lib/screens/product_page.dart' <<'DLJ_EOF_11'
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';

class ProductPage extends StatelessWidget {
  final Product product;
  final String? heroTag;
  const ProductPage({super.key, required this.product, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final p = product;
    final cur = store.currency;

    return Scaffold(
      backgroundColor: Palette.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 360,
            backgroundColor: Palette.navy,
            automaticallyImplyLeading: false,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Palette.ink),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: heroTag ?? 'grid-${p.id}',
                child: ProductImage(product: p, height: 360),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: const BoxDecoration(
                  color: Palette.bg,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Pill(p.kind.label, icon: p.kind.icon, color: p.kind.accent),
                        if (p.badge.isNotEmpty)
                          Pill(p.badge, icon: Icons.workspace_premium_rounded, color: Palette.coralDeep),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(p.name,
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.6)),
                    if (p.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(p.subtitle,
                          style: const TextStyle(color: Palette.muted, fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 20),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Precio',
                                  style: TextStyle(color: Palette.muted, fontWeight: FontWeight.w700)),
                              const Spacer(),
                              CurrencySwitch(value: cur, onChanged: store.setCurrency),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(money(p.priceIn(cur), cur),
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 14,
                            children: [
                              for (final c in Cur.values.where((c) => c != cur))
                                Text(money(p.priceIn(c), c),
                                    style: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text('Descripción',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      p.description.isEmpty ? 'Sin descripción.' : p.description,
                      style: const TextStyle(height: 1.5, color: Color(0xFF3B4663), fontSize: 15),
                    ),
                    const SizedBox(height: 22),
                    _InfoTile(
                      icon: p.isDigital ? Icons.bolt_rounded : Icons.local_shipping_rounded,
                      title: p.isDigital ? 'Entrega digital' : 'Envío dentro de Cuba',
                      text: p.isDigital
                          ? 'El enlace de descarga se libera en tu cuenta cuando se verifica el pago.'
                          : 'Coordinaremos la entrega contigo por teléfono o WhatsApp.',
                    ),
                    const SizedBox(height: 10),
                    const _InfoTile(
                      icon: Icons.shield_moon_rounded,
                      title: 'Pago verificado',
                      text: 'Cada pago se comprueba manualmente antes de entregar tu compra.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Palette.navy.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -6)),
            ],
          ),
          child: CoralButton(
            label: 'Agregar al carrito',
            icon: Icons.shopping_bag_rounded,
            onPressed: () {
              store.addToCart(p);
              toast(context, '${p.name} añadido al carrito');
            },
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _InfoTile({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Palette.navy.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Palette.navy, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(color: Palette.muted, height: 1.35, fontSize: 13.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
DLJ_EOF_11
cat > 'lib/screens/purchases_page.dart' <<'DLJ_EOF_12'
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});
  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis compras'),
        actions: [
          if (store.remote)
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () async {
                await store.refreshOrders();
                if (context.mounted) toast(context, 'Pedidos actualizados');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: Palette.navy,
                selectedForegroundColor: Colors.white,
              ),
              segments: [
                ButtonSegment(value: 0, label: Text('Pedidos (${store.orders.length})')),
                ButtonSegment(value: 1, label: Text('Descargas (${store.unlockedDownloads.length})')),
              ],
              selected: {tab},
              onSelectionChanged: (s) => setState(() => tab = s.first),
            ),
          ),
          Expanded(child: tab == 0 ? _Orders(store: store) : _Downloads(store: store)),
        ],
      ),
    );
  }
}

class _Orders extends StatelessWidget {
  final AppStore store;
  const _Orders({required this.store});

  @override
  Widget build(BuildContext context) {
    if (store.orders.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Aún no tienes pedidos',
        message: 'Cuando compres algo, aquí verás el estado de tu pago y tus descargas.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: store.orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => OrderCard(order: store.orders[i]),
    );
  }
}

class OrderCard extends StatelessWidget {
  final OrderRecord order;
  const OrderCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final o = order;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.code,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.4)),
              ),
              StatusChip(o.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(formatDate(o.createdAt), style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
          const Divider(height: 24),
          for (final l in o.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(l.kind.icon, size: 18, color: l.kind.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${l.name}  ×${l.qty}', style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(o.method.label, style: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${moneyPlain(o.amount, o.method.decimals)} ${o.method.currencyCode}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          if (o.status == OrderStatus.pending) ...[
            const SizedBox(height: 12),
            const _Note(
              icon: Icons.hourglass_top_rounded,
              color: Palette.warn,
              text: 'Estamos verificando tu pago. Si tardamos, envía el comprobante por WhatsApp.',
            ),
          ],
          if (o.status == OrderStatus.rejected) ...[
            const SizedBox(height: 12),
            _Note(
              icon: Icons.info_rounded,
              color: Palette.danger,
              text: o.sellerNote.isEmpty
                  ? 'No pudimos confirmar el pago. Contáctanos para revisarlo.'
                  : 'Motivo: ${o.sellerNote}',
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Note({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
          ],
        ),
      );
}

class _Downloads extends StatelessWidget {
  final AppStore store;
  const _Downloads({required this.store});

  @override
  Widget build(BuildContext context) {
    final items = store.unlockedDownloads;
    final waiting = store.orders
        .where((o) => o.status == OrderStatus.pending && o.hasDigital)
        .length;

    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.lock_clock_rounded,
        title: 'Sin descargas disponibles',
        message: waiting > 0
            ? 'Tienes $waiting pedido(s) esperando verificación. Tus descargas aparecerán aquí en cuanto se confirme el pago.'
            : 'Las apps y juegos que compres aparecerán aquí cuando se verifique tu pago.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final it = items[i];
        return SoftCard(
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: it.line.kind.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(it.line.kind.icon, color: it.line.kind.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.line.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text('Pedido ${it.order.code}',
                        style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Copiar enlace',
                onPressed: () => copyText(context, it.line.downloadUrl, 'Enlace'),
                icon: const Icon(Icons.copy_rounded, size: 19),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                tooltip: 'Descargar',
                style: IconButton.styleFrom(backgroundColor: Palette.coral),
                onPressed: () async {
                  final ok = await openUrl(it.line.downloadUrl);
                  if (!ok && context.mounted) toast(context, 'No se pudo abrir el enlace');
                },
                icon: const Icon(Icons.download_rounded, size: 20, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}
DLJ_EOF_12
cat > 'lib/screens/seller_pages.dart' <<'DLJ_EOF_13'
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/api.dart';
import '../models/models.dart';
import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';

// ───────────────────────── Acceso con PIN ─────────────────────────

class SellerGate extends StatelessWidget {
  const SellerGate({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (store.remote) {
      return store.api.isAdmin ? const SellerDashboard() : const _LoginScreen();
    }
    if (store.sellerUnlocked) return const SellerDashboard();
    return _PinScreen(creating: !store.hasPin);
  }
}

/// Entrada del vendedor cuando la tienda usa servidor: correo y contraseña.
class _LoginScreen extends StatefulWidget {
  const _LoginScreen();
  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  String? error;
  bool busy = false;
  bool hide = true;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _login(AppStore store) async {
    if (email.text.trim().isEmpty || pass.text.isEmpty) {
      setState(() => error = 'Escribe tu correo y tu contraseña');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await store.sellerLogin(email.text, pass.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Panel del vendedor')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
        children: [
          const Center(child: BrandLogo(size: 84)),
          const SizedBox(height: 22),
          const Text('Acceso de vendedor',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Entra con la cuenta que creaste en tu servidor.',
              textAlign: TextAlign.center, style: TextStyle(color: Palette.muted, height: 1.4)),
          const SizedBox(height: 26),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: fieldDec('Correo', icon: Icons.alternate_email_rounded),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pass,
            obscureText: hide,
            decoration: fieldDec('Contraseña', icon: Icons.lock_outline_rounded).copyWith(
              suffixIcon: IconButton(
                icon: Icon(hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => hide = !hide),
              ),
            ),
            onSubmitted: (_) => _login(store),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 22),
          CoralButton(
            label: busy ? 'Entrando…' : 'Entrar',
            icon: Icons.lock_open_rounded,
            onPressed: busy ? null : () => _login(store),
          ),
        ],
      ),
    );
  }
}

class _PinScreen extends StatefulWidget {
  final bool creating;
  const _PinScreen({required this.creating});
  @override
  State<_PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<_PinScreen> {
  final pin = TextEditingController();
  final pin2 = TextEditingController();
  String? error;

  @override
  void dispose() {
    pin.dispose();
    pin2.dispose();
    super.dispose();
  }

  Future<void> _submit(AppStore store) async {
    final v = pin.text.trim();
    if (widget.creating) {
      if (v.length < 4) {
        setState(() => error = 'Usa al menos 4 dígitos');
        return;
      }
      if (v != pin2.text.trim()) {
        setState(() => error = 'Los PIN no coinciden');
        return;
      }
      await store.createPin(v);
      return;
    }
    final lock = store.lockRemaining;
    if (lock != null) {
      setState(() => error = 'Demasiados intentos. Espera ${lock.inSeconds} s.');
      return;
    }
    if (!store.tryPin(v)) {
      final l = store.lockRemaining;
      setState(() {
        error = l != null ? 'Demasiados intentos. Espera ${l.inSeconds} s.' : 'PIN incorrecto';
        pin.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Panel del vendedor')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
        children: [
          const Center(child: BrandLogo(size: 84)),
          const SizedBox(height: 22),
          Text(widget.creating ? 'Crea tu PIN de vendedor' : 'Introduce tu PIN',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            widget.creating
                ? 'Protegerá tus pedidos, tarjetas y ajustes de cobro.'
                : 'Solo tú puedes verificar pagos y editar el catálogo.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.muted, height: 1.4),
          ),
          const SizedBox(height: 26),
          TextField(
            controller: pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w800),
            decoration: fieldDec(widget.creating ? 'Nuevo PIN' : 'PIN').copyWith(counterText: ''),
            onSubmitted: (_) => _submit(store),
          ),
          if (widget.creating) ...[
            const SizedBox(height: 12),
            TextField(
              controller: pin2,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.w800),
              decoration: fieldDec('Repite el PIN').copyWith(counterText: ''),
              onSubmitted: (_) => _submit(store),
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 22),
          CoralButton(
            label: widget.creating ? 'Crear PIN y entrar' : 'Entrar',
            icon: Icons.lock_open_rounded,
            onPressed: () => _submit(store),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Panel ─────────────────────────

class SellerDashboard extends StatefulWidget {
  const SellerDashboard({super.key});
  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = AppScope.of(context);
      if (!store.remote) return;
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) AppScope.of(context).refreshSeller();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel del vendedor'),
          actions: [
            IconButton(
              tooltip: 'Bloquear panel',
              icon: const Icon(Icons.lock_rounded),
              onPressed: () {
                store.lockSeller();
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                        label: 'Ventas verificadas',
                        value: money(store.verifiedCUP, Cur.cup),
                        icon: Icons.trending_up_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                        label: 'Por verificar',
                        value: '${store.pendingCount}',
                        icon: Icons.hourglass_top_rounded,
                        accent: store.pendingCount > 0 ? Palette.warn : Palette.muted),
                  ),
                ],
              ),
            ),
            const TabBar(
              labelColor: Palette.navy,
              unselectedLabelColor: Palette.muted,
              indicatorColor: Palette.coral,
              labelStyle: TextStyle(fontWeight: FontWeight.w800),
              tabs: [Tab(text: 'Pedidos'), Tab(text: 'Catálogo'), Tab(text: 'Ajustes')],
            ),
            const Expanded(
              child: TabBarView(children: [_OrdersTab(), _CatalogTab(), _SettingsTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  const _Stat({required this.label, required this.value, required this.icon, this.accent = Palette.ok});

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Palette.muted, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ───────────────────────── Pedidos ─────────────────────────

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();
  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  OrderStatus? filter;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final list = store.sellerList.where((o) => filter == null || o.status == filter).toList();

    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            children: [
              _FilterChip(label: 'Todos', selected: filter == null, onTap: () => setState(() => filter = null)),
              for (final s in OrderStatus.values)
                _FilterChip(
                  label: s.label,
                  selected: filter == s,
                  onTap: () => setState(() => filter = filter == s ? null : s),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: Palette.coral,
            onRefresh: store.refreshSeller,
            child: list.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 40),
                      EmptyState(
                        icon: Icons.inbox_rounded,
                        title: 'Sin pedidos',
                        message: 'Los pedidos aparecerán aquí cuando un cliente confirme su pago.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _SellerOrderCard(order: list[i], store: store),
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: Palette.navy,
        labelStyle: TextStyle(
            color: selected ? Colors.white : Palette.ink, fontWeight: FontWeight.w700, fontSize: 13),
        showCheckmark: false,
        backgroundColor: Colors.white,
        side: const BorderSide(color: Palette.line),
      ),
    );
  }
}

class _SmsResult extends StatelessWidget {
  final ({bool reference, bool amount}) r;
  const _SmsResult(this.r);

  @override
  Widget build(BuildContext context) {
    final ok = r.reference && r.amount;
    final text = ok
        ? '✓ Coinciden la referencia y el monto.'
        : r.reference
            ? '⚠ La referencia coincide, pero el monto no. Revísalo antes de verificar.'
            : '✗ No se encontró la referencia del pedido en ese texto.';
    final color = ok ? Palette.ok : (r.reference ? Palette.warn : Palette.danger);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, height: 1.35)),
    );
  }
}

class _SellerOrderCard extends StatelessWidget {
  final OrderRecord order;
  final AppStore store;
  const _SellerOrderCard({required this.order, required this.store});

  Future<void> _set(BuildContext context, OrderStatus s, {String note = '', String? ok}) async {
    try {
      await store.setOrderStatus(order, s, note: note);
      if (ok != null && context.mounted) toast(context, ok);
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  /// Compara el SMS de Transfermóvil con el pedido (referencia y monto).
  Future<void> _checkSms(BuildContext context) async {
    final ctrl = TextEditingController();
    ({bool reference, bool amount})? res;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Comprobar con el SMS'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pega el SMS o el comprobante que recibiste de Transfermóvil.',
                    style: TextStyle(fontSize: 13, color: Palette.muted)),
                const SizedBox(height: 10),
                TextField(controller: ctrl, maxLines: 4, decoration: fieldDec('Texto del SMS')),
                if (res != null) ...[
                  const SizedBox(height: 12),
                  _SmsResult(res!),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: () => setD(() => res = smsCheck(ctrl.text, order)),
              child: const Text('Comprobar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Pide confirmar que el dinero llegó de verdad antes de liberar la descarga.
  Future<void> _verify(BuildContext context) async {
    final o = order;
    final amount = '${moneyPlain(o.amount, o.method.decimals)} ${o.method.currencyCode}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Ya recibiste el dinero?'),
        content: Text(
          'Pedido ${o.code}\n$amount · ${o.method.label}\nReferencia: ${o.reference}\n\n'
          'Comprueba en tu banco o wallet que el pago llegó. '
          'Al verificar, el cliente podrá descargar su compra.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Palette.ok, minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, ya llegó'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _set(context, OrderStatus.verified, ok: 'Pago verificado · descargas liberadas');
    }
  }

  Future<void> _reject(BuildContext context) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar pago'),
        content: TextField(
          controller: note,
          maxLines: 2,
          decoration: fieldDec('Motivo (lo verá el cliente)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Palette.danger, minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    final text = note.text;
    if (ok == true && context.mounted) await _set(context, OrderStatus.rejected, note: text);
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final wa = onlyDigits(o.phone);
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.code,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.4)),
              ),
              StatusChip(o.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(formatDate(o.createdAt), style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          for (final l in o.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• ${l.name}  ×${l.qty}', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Text(o.method.label, style: const TextStyle(color: Palette.muted, fontWeight: FontWeight.w600))),
              Text('${moneyPlain(o.amount, o.method.decimals)} ${o.method.currencyCode}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          CopyRow(label: o.method.isCrypto ? 'TXID' : 'Nº de transacción', value: o.reference),
          if (o.method.isCrypto) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => openUrl(o.method == PayMethod.btc
                  ? 'https://mempool.space/tx/${o.reference}'
                  : 'https://tronscan.org/#/transaction/${o.reference}'),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: Text(o.method == PayMethod.btc ? 'Ver en Mempool' : 'Ver en Tronscan'),
            ),
          ],
          if (o.sellerNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Palette.warn.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(o.sellerNote, style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ),
          ],
          const SizedBox(height: 12),
          Text('${o.customerName} · ${o.phone}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (o.address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(o.address, style: const TextStyle(color: Palette.muted, fontSize: 13)),
            ),
          if (o.fromWallet.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Wallet: ${shortAddress(o.fromWallet)}',
                  style: const TextStyle(color: Palette.muted, fontSize: 13)),
            ),
          const SizedBox(height: 14),
          if (o.status == OrderStatus.pending && !o.method.isCrypto)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton.icon(
                onPressed: () => _checkSms(context),
                icon: const Icon(Icons.sms_rounded, size: 18),
                label: const Text('Comprobar con el SMS'),
              ),
            ),
          if (o.status == OrderStatus.pending)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Palette.danger, minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _reject(context),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Palette.ok, minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _verify(context),
                    child: const Text('Verificar pago'),
                  ),
                ),
              ],
            ),
          if (o.status == OrderStatus.verified && o.hasPhysical)
            FilledButton(
              onPressed: () => _set(context, OrderStatus.delivered, ok: 'Marcado como entregado'),
              child: const Text('Marcar como entregado'),
            ),
          if (o.status == OrderStatus.verified || o.status == OrderStatus.delivered)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.danger, minimumSize: const Size.fromHeight(48)),
                onPressed: () => _set(context, OrderStatus.pending,
                    ok: 'Devuelto a pendiente · descarga bloqueada'),
                child: const Text('Revertir a pendiente (bloquear descarga)'),
              ),
            ),
          if (o.status == OrderStatus.rejected)
            OutlinedButton(
              onPressed: () => _set(context, OrderStatus.pending),
              child: const Text('Reabrir para verificar'),
            ),
          if (wa.length >= 8) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => openUrl('https://wa.me/$wa'),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Escribir al cliente por WhatsApp'),
            ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Catálogo ─────────────────────────

class _CatalogTab extends StatelessWidget {
  const _CatalogTab();

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        CoralButton(
          label: 'Nuevo producto',
          icon: Icons.add_rounded,
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ProductFormPage())),
        ),
        const SizedBox(height: 16),
        if ((store.remote ? store.adminProducts : store.products).isEmpty)
          const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Catálogo vacío',
            message: 'Añade tu primer producto para empezar a vender.',
          ),
        for (final p in (store.remote ? store.adminProducts : store.products))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SoftCard(
              padding: const EdgeInsets.all(12),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ProductFormPage(product: p))),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(width: 62, height: 62, child: ProductImage(product: p, height: 62)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text('${p.kind.label} · ${money(p.priceCUP, Cur.cup)}',
                            style: const TextStyle(color: Palette.muted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline_rounded, color: Palette.danger),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Eliminar producto'),
                          content: Text('¿Eliminar «${p.name}» del catálogo?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Eliminar', style: TextStyle(color: Palette.danger))),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      try {
                        if (store.remote) {
                          await store.adminDeleteProduct(p.id);
                        } else {
                          await store.deleteProduct(p.id);
                        }
                      } on ApiException catch (e) {
                        if (context.mounted) toast(context, e.message);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ProductFormPage extends StatefulWidget {
  final Product? product;
  const ProductFormPage({super.key, this.product});
  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController name, subtitle, description, cup, mlc, usdt, imageUrl, download, badge;
  late ProductKind kind;
  late bool digital;
  late bool featured;
  late bool active;
  String imagePath = '';
  bool newImage = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    name = TextEditingController(text: p?.name ?? '');
    subtitle = TextEditingController(text: p?.subtitle ?? '');
    description = TextEditingController(text: p?.description ?? '');
    cup = TextEditingController(text: p == null ? '' : p.priceCUP.toStringAsFixed(0));
    mlc = TextEditingController(text: p == null ? '' : p.priceMLC.toString());
    usdt = TextEditingController(text: p == null ? '' : p.priceUSDT.toString());
    imageUrl = TextEditingController(text: p?.imageUrl ?? '');
    download = TextEditingController(text: p?.downloadUrl ?? '');
    badge = TextEditingController(text: p?.badge ?? '');
    kind = p?.kind ?? ProductKind.app;
    digital = p?.isDigital ?? true;
    featured = p?.featured ?? false;
    active = p?.active ?? true;
    imagePath = p?.imagePath ?? '';
    // Foto recuperada tras un cierre inesperado de la app (modo servidor).
    final lost = context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
    if (lost != null &&
        lost.remote &&
        lost.pendingImage.isNotEmpty &&
        File(lost.pendingImage).existsSync()) {
      imagePath = lost.pendingImage;
      newImage = true;
    }
  }

  @override
  void dispose() {
    for (final c in [name, subtitle, description, cup, mlc, usdt, imageUrl, download, badge]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  String? _price(String? v) {
    final n = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
    return (n == null || n < 0) ? 'Precio no válido' : null;
  }

  Future<void> _pickImage(AppStore store) async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1280, imageQuality: 80);
      if (x == null) return;
      // En modo servidor la foto se sube al guardar; en local se copia a la app.
      store.pendingImage = '';
      final saved = store.remote ? x.path : await store.persistImage(x.path);
      if (mounted) {
        setState(() {
          imagePath = saved;
          newImage = true;
        });
      }
    } catch (_) {
      if (mounted) toast(context, 'No se pudo cargar la imagen');
    }
  }

  Future<void> _save(AppStore store) async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    var url = imageUrl.text.trim();
    if (store.remote && newImage && imagePath.isNotEmpty) {
      try {
        url = await store.api.uploadImage(File(imagePath));
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() => busy = false);
        toast(context, 'No se pudo subir la foto: ${e.message}');
        return;
      }
    }
    final p = Product(
      id: widget.product?.id ?? (store.remote ? '' : DateTime.now().millisecondsSinceEpoch.toString()),
      name: name.text.trim(),
      subtitle: subtitle.text.trim(),
      description: description.text.trim(),
      kind: kind,
      priceCUP: _num(cup),
      priceMLC: _num(mlc),
      priceUSDT: _num(usdt),
      imageUrl: url,
      imagePath: store.remote ? '' : imagePath,
      downloadUrl: digital ? download.text.trim() : '',
      isDigital: digital,
      badge: badge.text.trim(),
      featured: featured,
      active: active,
    );
    try {
      if (store.remote) {
        await store.adminSaveProduct(p);
      } else {
        await store.upsertProduct(p);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      toast(context, e.message);
      return;
    }
    store.pendingImage = '';
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final preview = Product(
      id: 'preview',
      name: 'preview',
      kind: kind,
      priceCUP: 0,
      priceMLC: 0,
      priceUSDT: 0,
      isDigital: digital,
      imagePath: imagePath,
      imageUrl: imageUrl.text.trim(),
    );
    return Scaffold(
      appBar: AppBar(title: Text(widget.product == null ? 'Nuevo producto' : 'Editar producto')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
          children: [
            GestureDetector(
              onTap: () => _pickImage(store),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Stack(
                  children: [
                    SizedBox(height: 190, width: double.infinity, child: ProductImage(product: preview, height: 190)),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_rounded, size: 18),
                            SizedBox(width: 6),
                            Text('Elegir foto', style: TextStyle(fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ProductKind>(
              value: kind,
              decoration: fieldDec('Categoría', icon: Icons.category_rounded),
              items: [
                for (final k in ProductKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (k) => setState(() {
                kind = k ?? kind;
                digital = kind.digitalByDefault;
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: name,
              decoration: fieldDec('Nombre'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: subtitle, decoration: fieldDec('Subtítulo', hint: 'Ej. Óleo · 75×50 cm')),
            const SizedBox(height: 12),
            TextFormField(controller: description, maxLines: 4, decoration: fieldDec('Descripción')),
            const SizedBox(height: 18),
            const Text('Precios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                      controller: cup,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDec('CUP'),
                      validator: _price),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                      controller: mlc,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDec('MLC'),
                      validator: _price),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                      controller: usdt,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: fieldDec('USDT'),
                      validator: _price),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: digital,
              onChanged: (v) => setState(() => digital = v),
              title: const Text('Entrega digital', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Desactívalo para piezas físicas con envío'),
            ),
            if (digital) ...[
              TextFormField(
                controller: download,
                keyboardType: TextInputType.url,
                decoration: fieldDec('Enlace de descarga (APK)', icon: Icons.link_rounded),
              ),
              const SizedBox(height: 4),
              const Text('Solo se muestra al cliente cuando verificas su pago.',
                  style: TextStyle(color: Palette.muted, fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: imageUrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: fieldDec('URL de imagen (opcional)', icon: Icons.image_outlined),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: badge, decoration: fieldDec('Etiqueta', hint: 'Ej. Original, Popular, Pieza única')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: featured,
              onChanged: (v) => setState(() => featured = v),
              title: const Text('Mostrar en Destacados', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: active,
              onChanged: (v) => setState(() => active = v),
              title: const Text('Visible en la tienda', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Apágalo para ocultarlo sin borrarlo'),
            ),
            const SizedBox(height: 14),
            CoralButton(
              label: busy ? 'Guardando…' : 'Guardar producto',
              icon: Icons.check_rounded,
              onPressed: busy ? null : () => _save(store),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Ajustes de cobro ─────────────────────────

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  final _form = GlobalKey<FormState>();
  final business = TextEditingController();
  final whatsapp = TextEditingController();
  final cup = TextEditingController();
  final mlc = TextEditingController();
  final tron = TextEditingController();
  final trx = TextEditingController();
  final btc = TextEditingController();
  final btcPrice = TextEditingController();
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final c = AppScope.of(context).cfg;
    business.text = c.businessName;
    whatsapp.text = c.whatsapp;
    cup.text = formatCard(c.cupCard);
    mlc.text = formatCard(c.mlcCard);
    tron.text = c.tronAddress;
    trx.text = c.trxPerUsdt > 0 ? c.trxPerUsdt.toString() : '';
    btc.text = c.btcAddress;
    btcPrice.text = c.btcUsdtPrice > 0 ? c.btcUsdtPrice.toString() : '';
  }

  @override
  void dispose() {
    for (final c in [business, whatsapp, cup, mlc, tron, trx, btc, btcPrice]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _card(String? v) {
    final d = onlyDigits(v ?? '');
    if (d.isEmpty) return null;
    return d.length == 16 ? null : 'La tarjeta debe tener 16 dígitos';
  }

  Future<void> _save(AppStore store) async {
    if (!_form.currentState!.validate()) return;
    final c = store.cfg;
    c.businessName = business.text.trim().isEmpty ? 'HANDMADE D.L.J STORE' : business.text.trim();
    c.whatsapp = onlyDigits(whatsapp.text);
    c.cupCard = onlyDigits(cup.text);
    c.mlcCard = onlyDigits(mlc.text);
    c.tronAddress = tron.text.trim();
    c.trxPerUsdt = double.tryParse(trx.text.trim().replaceAll(',', '.')) ?? 0;
    c.btcAddress = btc.text.trim();
    c.btcUsdtPrice = double.tryParse(btcPrice.text.trim().replaceAll(',', '.')) ?? 0;
    try {
      if (store.remote) {
        await store.adminSaveSettings();
      } else {
        await store.saveConfig();
      }
      if (mounted) toast(context, 'Ajustes de cobro guardados');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  /// Rellena la tasa con el precio actual del mercado (puedes ajustarla a mano).
  Future<void> _fillRate(AppStore store, {required bool forBtc}) async {
    try {
      final usd = await store.api.fetchUsdPrice(forBtc ? 'bitcoin' : 'tron');
      if (!mounted) return;
      setState(() {
        if (forBtc) {
          btcPrice.text = usd.toStringAsFixed(2);
        } else {
          trx.text = (1 / usd).toStringAsFixed(4);
        }
      });
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _changePin(AppStore store) async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Cambiar PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: a,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: fieldDec('Nuevo PIN').copyWith(counterText: '')),
              const SizedBox(height: 10),
              TextField(
                  controller: b,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: fieldDec('Repite el PIN').copyWith(counterText: '', errorText: err)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: () async {
                if (a.text.trim().length < 4) {
                  setD(() => err = 'Mínimo 4 dígitos');
                  return;
                }
                if (a.text.trim() != b.text.trim()) {
                  setD(() => err = 'No coinciden');
                  return;
                }
                await store.createPin(a.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) toast(context, 'PIN actualizado');
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          const Text('Tu negocio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextFormField(controller: business, decoration: fieldDec('Nombre de la tienda', icon: Icons.storefront_rounded)),
          const SizedBox(height: 12),
          TextFormField(
            controller: whatsapp,
            keyboardType: TextInputType.phone,
            decoration: fieldDec('WhatsApp con código de país', hint: '5351234567', icon: Icons.chat_rounded),
            validator: (v) {
              final d = onlyDigits(v ?? '');
              return d.isEmpty || (d.length >= 8 && d.length <= 15) ? null : 'Número no válido';
            },
          ),
          const SizedBox(height: 24),
          const Text('Transfermóvil', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Tarjetas donde recibes los pagos. Déjalas vacías para desactivar el método.',
              style: TextStyle(color: Palette.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          TextFormField(
            controller: cup,
            keyboardType: TextInputType.number,
            decoration: fieldDec('Tarjeta CUP', hint: '9225 0000 0000 0000', icon: Icons.credit_card_rounded),
            validator: _card,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: mlc,
            keyboardType: TextInputType.number,
            decoration: fieldDec('Tarjeta MLC', hint: '9225 0000 0000 0000', icon: Icons.credit_card_rounded),
            validator: _card,
          ),
          const SizedBox(height: 24),
          const Text('Crypto (red TRON)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextFormField(
            controller: tron,
            decoration: fieldDec('Tu dirección TRON (T…)', icon: Icons.account_balance_wallet_rounded),
            validator: (v) {
              final a = (v ?? '').trim();
              return a.isEmpty || isValidTronAddress(a) ? null : 'Dirección TRON no válida';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: trx,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDec('TRX por cada 1 USDT (opcional)', hint: 'Vacío = no aceptar TRX', icon: Icons.swap_horiz_rounded),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return null;
              final n = double.tryParse(t.replaceAll(',', '.'));
              return (n == null || n <= 0) ? 'Tasa no válida' : null;
            },
          ),
          TextButton.icon(
            onPressed: () => _fillRate(store, forBtc: false),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Usar el precio actual de TRX'),
          ),
          const SizedBox(height: 24),
          const Text('Bitcoin', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Los precios se convierten con la tasa que fijes. Actualízala de vez en cuando.',
              style: TextStyle(color: Palette.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          TextFormField(
            controller: btc,
            decoration: fieldDec('Tu dirección Bitcoin (bc1… / 1… / 3…)', icon: Icons.currency_bitcoin_rounded),
            validator: (v) {
              final a = (v ?? '').trim();
              return a.isEmpty || isValidBtcAddress(a) ? null : 'Dirección Bitcoin no válida';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: btcPrice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: fieldDec('USDT por cada 1 BTC', hint: 'Vacío = no aceptar Bitcoin', icon: Icons.swap_horiz_rounded),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return null;
              final n = double.tryParse(t.replaceAll(',', '.'));
              return (n == null || n <= 0) ? 'Precio no válido' : null;
            },
          ),
          TextButton.icon(
            onPressed: () => _fillRate(store, forBtc: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Usar el precio actual de Bitcoin'),
          ),
          const SizedBox(height: 22),
          CoralButton(label: 'Guardar ajustes', icon: Icons.check_rounded, onPressed: () => _save(store)),
          if (!store.remote) ...[
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () => _changePin(store),
              icon: const Icon(Icons.password_rounded, size: 18),
              label: const Text('Cambiar PIN'),
            ),
          ],
        ],
      ),
    );
  }
}
DLJ_EOF_13
cat > 'lib/screens/shell.dart' <<'DLJ_EOF_14'
import 'package:flutter/material.dart';

import '../state/app_store.dart';
import '../utils/helpers.dart';
import 'account_page.dart';
import 'cart_page.dart';
import 'home_page.dart';
import 'purchases_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  AppStore? _store;

  @override
  void initState() {
    super.initState();
    _store = context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
    _store?.addListener(_onStore);
  }

  void _onStore() {
    final s = _store;
    if (s == null || !mounted || s.notice == null) return;
    final msg = s.notice!;
    s.notice = null;
    toast(context, msg);
  }

  @override
  void dispose() {
    _store?.removeListener(_onStore);
    super.dispose();
  }

  void goTo(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    final pages = <Widget>[
      const HomePage(),
      const CartPage(),
      const PurchasesPage(),
      const AccountPage(),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: goTo,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront_rounded),
            label: 'Tienda',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: store.cartCount > 0,
              label: Text('${store.cartCount}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: store.cartCount > 0,
              label: Text('${store.cartCount}'),
              child: const Icon(Icons.shopping_bag_rounded),
            ),
            label: 'Carrito',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Compras',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Cuenta',
          ),
        ],
      ),
    );
  }
}
DLJ_EOF_14
cat > 'lib/screens/wallet_page.dart' <<'DLJ_EOF_15'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_store.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';
import '../widgets/common.dart';

/// Vincula la wallet TRON del cliente a su cuenta. La dirección se valida
/// (Base58Check) para evitar errores de tecleo; la app nunca pide claves privadas.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});
  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final ctrl = TextEditingController();
  String? error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    ctrl.text = AppScope.of(context).profile.wallet;
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) setState(() => ctrl.text = d!.text!.trim());
  }

  Future<void> _save(AppStore store) async {
    final a = ctrl.text.trim();
    if (!isValidTronAddress(a)) {
      setState(() => error = 'Dirección TRON no válida. Debe empezar por T y tener 34 caracteres.');
      return;
    }
    store.profile.wallet = a;
    await store.saveProfile();
    if (!mounted) return;
    toast(context, 'Wallet vinculada correctamente');
    Navigator.of(context).pop();
  }

  Future<void> _unlink(AppStore store) async {
    store.profile.wallet = '';
    await store.saveProfile();
    if (!mounted) return;
    toast(context, 'Wallet desvinculada');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mi wallet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: Palette.hero,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.account_balance_wallet_rounded, color: Palette.gold, size: 34),
                SizedBox(height: 14),
                Text('Vincula tu wallet TRON',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(
                  'Pega la dirección pública de tu wallet (TronLink, Trust Wallet, etc.) '
                  'para que tus pagos en USDT o TRX se identifiquen más rápido.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: ctrl,
            minLines: 1,
            maxLines: 2,
            onChanged: (_) => setState(() => error = null),
            decoration: fieldDec('Dirección pública (T…)', icon: Icons.link_rounded).copyWith(
              errorText: error,
              suffixIcon: IconButton(
                tooltip: 'Pegar',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _paste,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF7EF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_rounded, color: Palette.ok, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Solo guardamos la dirección pública. Nunca te pediremos tu frase semilla ni tu clave privada.',
                    style: TextStyle(height: 1.35, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          CoralButton(label: 'Guardar wallet', icon: Icons.check_rounded, onPressed: () => _save(store)),
          if (store.profile.hasWallet) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => _unlink(store), child: const Text('Desvincular wallet')),
          ],
        ],
      ),
    );
  }
}
DLJ_EOF_15
cat > 'lib/state/app_store.dart' <<'DLJ_EOF_16'
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/api.dart';
import '../models/models.dart';
import '../utils/helpers.dart';

List<Product> seedProducts() => const [
      Product(
        id: 'seed-app-1',
        name: 'Gestor de Ventas Pro',
        subtitle: 'Android · Productividad',
        description:
            'Controla inventario, ventas y ganancias desde tu teléfono, sin internet. '
            'Recibirás el enlace del APK en cuanto se verifique tu pago.',
        kind: ProductKind.app,
        priceCUP: 3500,
        priceMLC: 12,
        priceUSDT: 12,
        downloadUrl: '',
        isDigital: true,
        badge: 'Popular',
        featured: true,
      ),
      Product(
        id: 'seed-game-1',
        name: 'Habana Runner',
        subtitle: 'Android · Aventura',
        description: 'Corre por las calles de La Habana esquivando obstáculos. APK tras verificar el pago.',
        kind: ProductKind.game,
        priceCUP: 1500,
        priceMLC: 5,
        priceUSDT: 5,
        isDigital: true,
        badge: 'Top',
        featured: true,
      ),
      Product(
        id: 'seed-craft-1',
        name: 'Lámpara PVC LED pintada',
        subtitle: 'Pieza hecha a mano · LED',
        description:
            'Lámpara de PVC calado y pintada a mano, con iluminación LED. Cada pieza es única. '
            'Envío físico dentro de Cuba.',
        kind: ProductKind.craft,
        priceCUP: 9500,
        priceMLC: 30,
        priceUSDT: 30,
        isDigital: false,
        badge: 'Hecho a mano',
        featured: true,
      ),
      Product(
        id: 'seed-paint-1',
        name: 'Esencia cubana',
        subtitle: 'Óleo sobre lienzo · 75×50 cm',
        description: 'Pintura original firmada por el artista. Envío físico en Cuba.',
        kind: ProductKind.painting,
        priceCUP: 85000,
        priceMLC: 270,
        priceUSDT: 270,
        isDigital: false,
        badge: 'Original',
        featured: true,
      ),
      Product(
        id: 'seed-sculpt-1',
        name: 'Figura en relieve',
        subtitle: 'Escultura artesanal',
        description: 'Escultura modelada a mano con acabado artístico. Envío físico en Cuba.',
        kind: ProductKind.sculpture,
        priceCUP: 24000,
        priceMLC: 75,
        priceUSDT: 75,
        isDigital: false,
        badge: 'Pieza única',
      ),
      Product(
        id: 'seed-art-1',
        name: 'Grabado artístico',
        subtitle: 'Edición limitada',
        description: 'Grabado impreso de forma artesanal en edición limitada y numerada.',
        kind: ProductKind.art,
        priceCUP: 12000,
        priceMLC: 38,
        priceUSDT: 38,
        isDigital: false,
        badge: 'Edición limitada',
      ),
    ];

class AppStore extends ChangeNotifier {
  List<Product> products = [];
  final List<CartItem> cart = [];
  StoreConfig cfg = StoreConfig();
  CustomerProfile profile = CustomerProfile();
  List<OrderRecord> orders = [];
  Cur currency = Cur.cup;
  bool loaded = false;

  // Modo servidor (Supabase). Si no hay datos de servidor, todo es local.
  final Api api = Api();
  final bool remote = kRemote;
  bool syncing = false;
  String? syncError;
  List<OrderRecord> sellerOrders = [];
  List<Product> adminProducts = [];
  bool _sellerVisible = !kRemote;
  // Foto elegida cuando Android cerró la app mientras estaba abierta la galería.
  String pendingImage = '';
  // Aviso para el cliente cuando el vendedor verifica o rechaza su pedido.
  String? notice;
  int _aboutTaps = 0;
  Timer? _timer;

  // Sesión del vendedor (solo en memoria).
  bool sellerUnlocked = false;
  int _failedPin = 0;
  DateTime? _lockedUntil;

  static const _kProducts = 'djl2_products';
  static const _kCfg = 'djl2_cfg';
  static const _kProfile = 'djl2_profile';
  static const _kOrders = 'djl2_orders';
  static const _kCurrency = 'djl2_currency';
  static const _kSellerVisible = 'djl2_seller_visible';

  // ─────────── Carga / guardado ───────────

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString(_kProducts);
      if (raw != null && raw.isNotEmpty) {
        products = (jsonDecode(raw) as List)
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (!remote) {
        products = seedProducts();
        await _saveProducts();
      }
      final c = p.getString(_kCfg);
      if (c != null) cfg = StoreConfig.fromJson(jsonDecode(c) as Map<String, dynamic>);
      final pr = p.getString(_kProfile);
      if (pr != null) profile = CustomerProfile.fromJson(jsonDecode(pr) as Map<String, dynamic>);
      final o = p.getString(_kOrders);
      if (o != null) {
        orders = (jsonDecode(o) as List)
            .map((e) => OrderRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      final cur = p.getString(_kCurrency);
      currency = Cur.values.firstWhere((e) => e.name == cur, orElse: () => Cur.cup);
      if (remote) _sellerVisible = p.getBool(_kSellerVisible) ?? false;
    } catch (_) {
      // Si algún dato guardado está dañado, arrancamos con el catálogo base.
      if (products.isEmpty && !remote) products = seedProducts();
    }
    // Si Android cerró la app mientras se elegía una foto, la recuperamos.
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (!lost.isEmpty && lost.file != null) pendingImage = lost.file!.path;
    } catch (_) {}
    loaded = true;
    notifyListeners();
    if (remote) {
      unawaited(refreshRemote());
      unawaited(refreshOrders());
      _timer = Timer.periodic(const Duration(seconds: 45), (_) {
        if (orders.any((o) => o.status == OrderStatus.pending)) {
          unawaited(refreshOrders());
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ─────────── Servidor ───────────

  Future<void> _persistCfg() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCfg, jsonEncode(cfg.toJson()));
  }

  /// Descarga catálogo y datos de cobro del servidor (con caché local si no hay red).
  Future<void> refreshRemote() async {
    if (!remote) return;
    syncing = true;
    notifyListeners();
    try {
      final list = await api.fetchProducts();
      final s = await api.fetchSettings();
      products = list;
      cfg
        ..businessName = s.businessName
        ..whatsapp = s.whatsapp
        ..cupCard = s.cupCard
        ..mlcCard = s.mlcCard
        ..tronAddress = s.tronAddress
        ..trxPerUsdt = s.trxPerUsdt
        ..btcAddress = s.btcAddress
        ..btcUsdtPrice = s.btcUsdtPrice;
      // Mantener el carrito alineado con el catálogo actual.
      final old = cart.map((c) => MapEntry(c.product.id, c.qty)).toList();
      cart.clear();
      for (final e in old) {
        final i = products.indexWhere((p) => p.id == e.key);
        if (i >= 0) cart.add(CartItem(products[i], e.value));
      }
      await _saveProducts();
      await _persistCfg();
      syncError = null;
    } on ApiException catch (e) {
      syncError = e.message;
    } catch (_) {
      syncError = 'No se pudo actualizar la tienda';
    }
    syncing = false;
    notifyListeners();
  }

  /// Actualiza estado y descargas de los pedidos de este teléfono.
  Future<void> refreshOrders() async {
    if (!remote) return;
    final tokens = orders.map((o) => o.accessToken).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return;
    try {
      final rows = await api.myOrders(tokens);
      final byId = {for (final r in rows) r['id'].toString(): r};
      final before = {for (final o in orders) o.id: o.status};
      var changed = false;
      orders = [
        for (final o in orders)
          if (byId.containsKey(o.id))
            orderFromRow(byId[o.id]!, token: o.accessToken)
          else
            o
      ];
      for (final o in orders) {
        if (byId.containsKey(o.id)) changed = true;
        if (before[o.id] == OrderStatus.pending) {
          if (o.status.unlocksDownloads) {
            notice = 'Tu pago del pedido ${o.code} fue verificado. Ya puedes descargar tu compra.';
          } else if (o.status == OrderStatus.rejected) {
            notice = 'Tu pedido ${o.code} no pudo verificarse. Revisa los detalles en Compras.';
          }
        }
      }
      if (changed) {
        await _saveOrders();
        notifyListeners();
      }
    } catch (_) {
      // Sin red: se conserva lo último guardado.
    }
  }

  Future<void> sellerLogin(String email, String password) async {
    await api.login(email, password);
    try {
      sellerOrders = await api.adminOrders();
      adminProducts = await api.adminProducts();
    } on ApiException catch (e) {
      api.logout();
      throw ApiException(
          e.message == 'No autorizado' ? 'Esta cuenta no es de vendedor' : e.message);
    }
    notifyListeners();
  }

  Future<void> refreshSeller() async {
    if (!remote || !api.isAdmin) return;
    try {
      sellerOrders = await api.adminOrders();
      adminProducts = await api.adminProducts();
    } on ApiException catch (e) {
      syncError = e.message;
    }
    notifyListeners();
  }

  Future<void> adminSaveProduct(Product p) async {
    await api.adminSaveProduct(p);
    await refreshSeller();
    await refreshRemote();
  }

  Future<void> adminDeleteProduct(String id) async {
    await api.adminDeleteProduct(id);
    await refreshSeller();
    await refreshRemote();
  }

  Future<void> adminSaveSettings() async {
    await api.adminSaveSettings(cfg);
    await _persistCfg();
    notifyListeners();
  }

  // Entrada discreta al panel del vendedor (7 toques en «Información»).
  bool get sellerEntryVisible => _sellerVisible;

  Future<bool> aboutTap() async {
    if (_sellerVisible) return false;
    _aboutTaps++;
    if (_aboutTaps < 7) return false;
    _sellerVisible = true;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSellerVisible, true);
    notifyListeners();
    return true;
  }

  Future<void> _saveProducts() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProducts, jsonEncode(products.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveOrders() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOrders, jsonEncode(orders.map((e) => e.toJson()).toList()));
  }

  Future<void> saveConfig() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCfg, jsonEncode(cfg.toJson()));
    notifyListeners();
  }

  Future<void> saveProfile() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProfile, jsonEncode(profile.toJson()));
    notifyListeners();
  }

  Future<void> setCurrency(Cur c) async {
    currency = c;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCurrency, c.name);
    notifyListeners();
  }

  // ─────────── Catálogo ───────────

  Future<void> upsertProduct(Product product) async {
    final i = products.indexWhere((e) => e.id == product.id);
    if (i >= 0) {
      products[i] = product;
    } else {
      products.insert(0, product);
    }
    await _saveProducts();
    notifyListeners();
  }

  Future<void> deleteProduct(String id) async {
    products.removeWhere((e) => e.id == id);
    cart.removeWhere((c) => c.product.id == id);
    await _saveProducts();
    notifyListeners();
  }

  /// Copia la imagen elegida a la carpeta de la app para que no se pierda.
  Future<String> persistImage(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final ext = sourcePath.contains('.') ? sourcePath.split('.').last : 'jpg';
    final dest = '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(sourcePath).copy(dest);
    return dest;
  }

  // ─────────── Carrito ───────────

  void addToCart(Product product) {
    final ex = cart.where((c) => c.product.id == product.id);
    if (ex.isNotEmpty) {
      ex.first.qty++;
    } else {
      cart.add(CartItem(product));
    }
    notifyListeners();
  }

  void changeQty(CartItem item, int delta) {
    item.qty += delta;
    if (item.qty <= 0) cart.remove(item);
    notifyListeners();
  }

  void removeFromCart(CartItem item) {
    cart.remove(item);
    notifyListeners();
  }

  int get cartCount => cart.fold(0, (s, i) => s + i.qty);
  double cartTotal(Cur c) => cart.fold(0.0, (s, i) => s + i.product.priceIn(c) * i.qty);
  bool get cartHasPhysical => cart.any((c) => !c.product.isDigital);

  // ─────────── Pedidos ───────────

  double amountFor(PayMethod m) => switch (m) {
        PayMethod.transfermovilCup => cartTotal(Cur.cup),
        PayMethod.transfermovilMlc => cartTotal(Cur.mlc),
        PayMethod.usdtTrc20 => cartTotal(Cur.usdt),
        PayMethod.trx => cartTotal(Cur.usdt) * cfg.trxPerUsdt,
        PayMethod.btc =>
          cfg.btcUsdtPrice > 0 ? cartTotal(Cur.usdt) / cfg.btcUsdtPrice : 0,
      };

  Future<OrderRecord> createOrder({
    required PayMethod method,
    required String reference,
    required String name,
    required String phone,
    String address = '',
    String fromWallet = '',
  }) async {
    final lines = cart
        .map((c) => OrderLine(
              productId: c.product.id,
              name: c.product.name,
              kind: c.product.kind,
              qty: c.qty,
              unitCUP: c.product.priceCUP,
              unitMLC: c.product.priceMLC,
              unitUSDT: c.product.priceUSDT,
              isDigital: c.product.isDigital,
              // En modo servidor el enlace llega solo cuando el pago se verifica.
              downloadUrl: remote ? '' : c.product.downloadUrl,
            ))
        .toList();
    var id = DateTime.now().millisecondsSinceEpoch.toString();
    var code = 'DLJ-${randomToken(6)}';
    var token = '';
    var amount = amountFor(method);
    var created = DateTime.now();
    if (remote) {
      final r = await api.createOrder(
        cart: List.of(cart),
        method: method,
        reference: reference.trim(),
        name: name.trim(),
        phone: phone.trim(),
        address: address.trim(),
        wallet: fromWallet.trim(),
      );
      id = r['id'].toString();
      code = r['code'].toString();
      token = r['access_token'].toString();
      amount = double.tryParse(r['amount'].toString()) ?? amount;
      created = DateTime.tryParse(r['created_at'].toString())?.toLocal() ?? created;
    }
    final order = OrderRecord(
      id: id,
      code: code,
      accessToken: token,
      lines: lines,
      method: method,
      amount: amount,
      reference: reference.trim(),
      customerName: name.trim(),
      phone: phone.trim(),
      address: address.trim(),
      fromWallet: fromWallet.trim(),
      createdAt: created,
    );
    orders.insert(0, order);
    cart.clear();
    profile
      ..name = name.trim()
      ..phone = phone.trim();
    if (address.trim().isNotEmpty) profile.address = address.trim();
    await _saveOrders();
    await saveProfile();
    return order;
  }

  Future<void> setOrderStatus(OrderRecord o, OrderStatus s, {String note = ''}) async {
    if (remote) await api.adminSetStatus(o.id, s, note.trim());
    o.status = s;
    if (note.trim().isNotEmpty) o.sellerNote = note.trim();
    if (!remote) await _saveOrders();
    notifyListeners();
  }

  /// Pedidos que ve el vendedor: del servidor, o los locales si no hay servidor.
  List<OrderRecord> get sellerList => remote ? sellerOrders : orders;

  /// Descargas liberadas: solo de pedidos con pago verificado por el vendedor.
  List<({OrderRecord order, OrderLine line})> get unlockedDownloads => [
        for (final o in orders)
          if (o.status.unlocksDownloads)
            for (final l in o.lines)
              if (l.isDigital && l.downloadUrl.isNotEmpty) (order: o, line: l),
      ];

  int get pendingCount => sellerList.where((o) => o.status == OrderStatus.pending).length;
  double get verifiedCUP => sellerList
      .where((o) => o.status.unlocksDownloads)
      .fold(0.0, (s, o) => s + o.totalCUP);

  // ─────────── PIN del vendedor ───────────

  bool get hasPin => cfg.pinHash.isNotEmpty;

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Duration? get lockRemaining {
    final l = _lockedUntil;
    if (l == null) return null;
    final d = l.difference(DateTime.now());
    return d.isNegative ? null : d;
  }

  Future<void> createPin(String pin) async {
    cfg.pinSalt = randomToken(16);
    cfg.pinHash = _hash(pin, cfg.pinSalt);
    sellerUnlocked = true;
    await saveConfig();
  }

  bool tryPin(String pin) {
    if (lockRemaining != null) return false;
    if (_hash(pin, cfg.pinSalt) == cfg.pinHash) {
      _failedPin = 0;
      sellerUnlocked = true;
      notifyListeners();
      return true;
    }
    _failedPin++;
    if (_failedPin >= 5) {
      _failedPin = 0;
      _lockedUntil = DateTime.now().add(const Duration(seconds: 60));
    }
    return false;
  }

  void lockSeller() {
    if (remote) {
      api.logout();
      sellerOrders = [];
      adminProducts = [];
    }
    sellerUnlocked = false;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppStore> {
  const AppScope({super.key, required AppStore store, required super.child})
      : super(notifier: store);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope no encontrado');
    return scope!.notifier!;
  }
}
DLJ_EOF_16
cat > 'lib/theme/app_theme.dart' <<'DLJ_EOF_17'
import 'package:flutter/material.dart';

/// Paleta tomada del logo de HANDMADE D.L.J STORE: azul marino profundo,
/// trazo coral y un dorado discreto para los detalles premium.
class Palette {
  static const navyDeep = Color(0xFF030F26);
  static const navy = Color(0xFF061C41);
  static const navySoft = Color(0xFF0E2B5C);
  static const coral = Color(0xFFF87171);
  static const coralDeep = Color(0xFFE5484D);
  static const gold = Color(0xFFE6C27A);
  static const bg = Color(0xFFF4F6FB);
  static const ink = Color(0xFF0B1630);
  static const muted = Color(0xFF6B7794);
  static const line = Color(0xFFE3E8F2);
  static const ok = Color(0xFF16A34A);
  static const warn = Color(0xFFF59E0B);
  static const danger = Color(0xFFDC2626);

  static const hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyDeep, navy, navySoft],
  );

  static const coralGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [coral, coralDeep],
  );
}

List<BoxShadow> softShadow([double opacity = 0.07]) => [
      BoxShadow(
        color: Palette.navy.withOpacity(opacity),
        blurRadius: 24,
        offset: const Offset(0, 10),
      ),
    ];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.navy,
    primary: Palette.navy,
    secondary: Palette.coral,
    brightness: Brightness.light,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Palette.ink,
      displayColor: Palette.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.bg,
      foregroundColor: Palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Palette.ink,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(color: Palette.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.navy, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.navy,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: Palette.line, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 12,
      height: 68,
      indicatorColor: Palette.coral.withOpacity(0.16),
      labelTextStyle: MaterialStateProperty.resolveWith((states) {
        final sel = states.contains(MaterialState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
          color: sel ? Palette.navy : Palette.muted,
        );
      }),
      iconTheme: MaterialStateProperty.resolveWith((states) {
        final sel = states.contains(MaterialState.selected);
        return IconThemeData(color: sel ? Palette.navy : Palette.muted);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.navy,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerColor: Palette.line,
  );
}
DLJ_EOF_17
cat > 'lib/utils/helpers.dart' <<'DLJ_EOF_18'
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';

final _cupFmt = NumberFormat('#,##0', 'en_US');
final _decFmt = NumberFormat('#,##0.00', 'en_US');

String money(double v, Cur c) =>
    '${c == Cur.cup ? _cupFmt.format(v) : _decFmt.format(v)} ${c.code}';

String moneyPlain(double v, int decimals) => decimals == 0
    ? _cupFmt.format(v)
    : (decimals == 2 ? _decFmt.format(v) : v.toStringAsFixed(decimals));

String formatDate(DateTime d) => DateFormat('dd/MM/yyyy · HH:mm').format(d);

/// Agrupa una tarjeta en bloques de 4 dígitos: 9225 0000 0000 0000
String formatCard(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i % 4 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return buf.toString();
}

String onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

String shortAddress(String a) =>
    a.length <= 14 ? a : '${a.substring(0, 6)}…${a.substring(a.length - 6)}';

const _tokenAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
final _rng = Random.secure();

String randomToken(int len) =>
    List.generate(len, (_) => _tokenAlphabet[_rng.nextInt(_tokenAlphabet.length)]).join();

/// Valida una dirección TRON (Base58Check, prefijo 0x41, 34 caracteres que
/// empiezan por «T»). Detecta errores de tecleo antes de que alguien envíe dinero.
bool isValidTronAddress(String address) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  final a = address.trim();
  if (a.length != 34 || a[0] != 'T') return false;
  var n = BigInt.zero;
  final base = BigInt.from(58);
  for (final ch in a.split('')) {
    final i = alphabet.indexOf(ch);
    if (i < 0) return false;
    n = n * base + BigInt.from(i);
  }
  final bytes = List<int>.filled(25, 0);
  final mask = BigInt.from(0xff);
  for (var i = 24; i >= 0; i--) {
    bytes[i] = (n & mask).toInt();
    n = n >> 8;
  }
  if (n != BigInt.zero || bytes[0] != 0x41) return false;
  final check = sha256.convert(sha256.convert(bytes.sublist(0, 21)).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (check[i] != bytes[21 + i]) return false;
  }
  return true;
}

const _b58Alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
const _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

/// Base58Check de 25 bytes (versión + 20 bytes + 4 de checksum).
bool _base58Check25(String a, Set<int> versions) {
  var n = BigInt.zero;
  final base = BigInt.from(58);
  for (final ch in a.split('')) {
    final i = _b58Alphabet.indexOf(ch);
    if (i < 0) return false;
    n = n * base + BigInt.from(i);
  }
  final bytes = List<int>.filled(25, 0);
  final mask = BigInt.from(0xff);
  for (var i = 24; i >= 0; i--) {
    bytes[i] = (n & mask).toInt();
    n = n >> 8;
  }
  if (n != BigInt.zero || !versions.contains(bytes[0])) return false;
  final check = sha256.convert(sha256.convert(bytes.sublist(0, 21)).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (check[i] != bytes[21 + i]) return false;
  }
  return true;
}

int _bech32Polymod(List<int> values) {
  const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var chk = 1;
  for (final v in values) {
    final b = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if (((b >> i) & 1) == 1) chk ^= gen[i];
    }
  }
  return chk;
}

bool _isValidBech32Btc(String addr) {
  if (addr != addr.toLowerCase() && addr != addr.toUpperCase()) return false;
  final a = addr.toLowerCase();
  final pos = a.lastIndexOf('1');
  if (pos < 1 || pos + 7 > a.length || a.length > 90) return false;
  final hrp = a.substring(0, pos);
  if (hrp != 'bc') return false;
  final data = <int>[];
  for (final ch in a.substring(pos + 1).split('')) {
    final i = _bech32Charset.indexOf(ch);
    if (i < 0) return false;
    data.add(i);
  }
  final values = <int>[
    ...hrp.codeUnits.map((c) => c >> 5),
    0,
    ...hrp.codeUnits.map((c) => c & 31),
    ...data,
  ];
  final pm = _bech32Polymod(values);
  final witnessVersion = data[0];
  if (witnessVersion > 16) return false;
  if (witnessVersion == 0) {
    if (pm != 1) return false;
  } else if (pm != 0x2bc830a3) {
    return false;
  }
  final programBytes = ((data.length - 7) * 5) ~/ 8;
  if (witnessVersion == 0 && programBytes != 20 && programBytes != 32) return false;
  return programBytes >= 2 && programBytes <= 40;
}

/// Valida una dirección Bitcoin de mainnet (1…, 3…, bc1…) comprobando su checksum,
/// para detectar errores de tecleo antes de que alguien envíe dinero.
bool isValidBtcAddress(String address) {
  final a = address.trim();
  if (a.length < 14 || a.length > 90) return false;
  if (a.toLowerCase().startsWith('bc1')) return _isValidBech32Btc(a);
  if (a[0] != '1' && a[0] != '3') return false;
  return _base58Check25(a, a[0] == '1' ? {0x00} : {0x05});
}

/// Compara el texto de un SMS o comprobante de Transfermóvil con un pedido.
({bool reference, bool amount}) smsCheck(String text, OrderRecord order) {
  final norm = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final ref = order.reference.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final refOk = ref.length >= 4 && norm.contains(ref);
  final tolerance = order.method.decimals == 0 ? 0.5 : 0.011;
  var amountOk = false;
  for (final m in RegExp(r'\d[\d.,]*').allMatches(text)) {
    final t = m.group(0)!;
    final candidates = <double?>[
      double.tryParse(t.replaceAll(',', '')),
      double.tryParse(t.replaceAll('.', '').replaceAll(',', '.')),
    ];
    for (final c in candidates) {
      if (c != null && (c - order.amount).abs() < tolerance) amountOk = true;
    }
  }
  return (reference: refOk, amount: amountOk);
}

bool isValidTxId(String s) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(s.trim());

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(message)));
}

Future<void> copyText(BuildContext context, String text, [String what = 'Copiado']) async {
  await Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.lightImpact();
  if (context.mounted) toast(context, '$what al portapapeles');
}

Future<bool> openUrl(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
DLJ_EOF_18
cat > 'lib/widgets/common.dart' <<'DLJ_EOF_19'
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/helpers.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        'assets/images/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Palette.navy,
          child: Icon(Icons.storefront_rounded, color: Colors.white, size: size * 0.55),
        ),
      ),
    );
  }
}

/// Imagen del producto: archivo local → URL → degradado con icono.
class ProductImage extends StatelessWidget {
  final Product product;
  final double? height;
  final BoxFit fit;
  const ProductImage({super.key, required this.product, this.height, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final accent = product.kind.accent;
    final placeholder = Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.95), Palette.navy],
        ),
      ),
      child: Center(
        child: Icon(product.kind.icon, size: 46, color: Colors.white.withOpacity(0.9)),
      ),
    );
    if (product.imagePath.isNotEmpty && File(product.imagePath).existsSync()) {
      return Image.file(File(product.imagePath),
          height: height, width: double.infinity, fit: fit);
    }
    if (product.imageUrl.isNotEmpty) {
      return Image.network(
        product.imageUrl,
        height: height,
        width: double.infinity,
        fit: fit,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (c, child, p) => p == null ? child : placeholder,
      );
    }
    return placeholder;
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!,
                  style: const TextStyle(
                      color: Palette.coralDeep, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
        boxShadow: softShadow(),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class CoralButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const CoralButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: Palette.coralGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: Palette.coral.withOpacity(0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 8))
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                ],
                Text(label,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final OrderStatus status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: status.color),
          const SizedBox(width: 5),
          Text(status.label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: status.color)),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  const Pill(this.text, {super.key, this.icon, this.color = Palette.navy});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Palette.navy.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: Palette.navy.withOpacity(0.55)),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Palette.muted, height: 1.4)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Fila «etiqueta / valor» con botón de copiar.
class CopyRow extends StatelessWidget {
  final String label;
  final String value;
  final String? display;
  final bool mono;
  const CopyRow({
    super.key,
    required this.label,
    required this.value,
    this.display,
    this.mono = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Palette.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: Palette.muted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(display ?? value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: mono ? 'monospace' : null)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () => copyText(context, value, label),
          ),
        ],
      ),
    );
  }
}

class CurrencySwitch extends StatelessWidget {
  final Cur value;
  final ValueChanged<Cur> onChanged;
  final bool dark;
  const CurrencySwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withOpacity(0.1) : Palette.line.withOpacity(0.7),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in Cur.values)
            GestureDetector(
              onTap: () => onChanged(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: c == value ? (dark ? Palette.coral : Palette.navy) : Colors.transparent,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  c.code,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: c == value
                        ? Colors.white
                        : (dark ? Colors.white70 : Palette.muted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

InputDecoration fieldDec(String label, {String? hint, IconData? icon}) => InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
    );
DLJ_EOF_19
cat > 'pubspec.yaml' <<'DLJ_EOF_20'
name: tienda_cuba
description: HANDMADE D.L.J STORE - Tienda de apps, juegos, arte, pintura, escultura y artesanías con pagos Transfermóvil CUP/MLC y crypto TRC20
publish_to: 'none'
version: 2.2.0+4

environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  shared_preferences: ^2.2.2
  image_picker: ^1.0.7
  path_provider: ^2.1.2
  url_launcher: ^6.2.4
  qr_flutter: ^4.1.0
  crypto: ^3.0.3
  intl: ^0.19.0
  http: ^1.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1

flutter:
  uses-material-design: true
  assets:
    - assets/images/logo.png
DLJ_EOF_20
cat > 'analysis_options.yaml' <<'DLJ_EOF_21'
include: package:flutter_lints/flutter.yaml
linter:
  rules:
    prefer_const_constructors: false
    avoid_print: false
DLJ_EOF_21
base64 -d > assets/images/logo.png <<'DLJ_B64'
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
DLJ_B64

echo "▶ Generando la parte Android con Flutter…"
TMP_DIR="$(mktemp -d)"
( cd "$TMP_DIR" && flutter create --platforms=android --org com.dlj --project-name tienda_cuba --no-pub app >/dev/null )
cp -r "$TMP_DIR/app/android" ./android
rm -rf "$TMP_DIR"

echo "▶ Aplicando permisos, nombre e íconos…"
pip install --quiet pillow >/dev/null 2>&1 || true
python3 - <<'PY'
import re, os
from PIL import Image

# --- AndroidManifest: internet, nombre y consultas para abrir enlaces ---
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()
if 'android.permission.INTERNET' not in s:
    s = re.sub(r'(<manifest[^>]*>)', r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>', s, count=1)
s = re.sub(r'android:label="[^"]*"', 'android:label="D.L.J STORE"', s, count=1)
intents = ''.join(
    '\n        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="%s"/></intent>' % sc
    for sc in ('https', 'http', 'whatsapp', 'tron', 'bitcoin')
)
if '<queries>' in s:
    s = s.replace('<queries>', '<queries>' + intents, 1)
else:
    s = s.replace('</manifest>', '    <queries>' + intents + '\n    </queries>\n</manifest>', 1)
open(p, 'w', encoding='utf-8').write(s)

# --- Fondo de arranque azul marino (color como recurso, la forma segura para aapt2) ---
os.makedirs('android/app/src/main/res/values', exist_ok=True)
open('android/app/src/main/res/values/dlj_colors.xml', 'w', encoding='utf-8').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="dlj_navy">#061C41</color>\n</resources>\n')
for d in ('drawable', 'drawable-v21'):
    f = 'android/app/src/main/res/%s/launch_background.xml' % d
    if os.path.exists(f):
        t = open(f, encoding='utf-8').read()
        t = t.replace('@android:color/white', '@color/dlj_navy').replace('?android:colorBackground', '@color/dlj_navy')
        open(f, 'w', encoding='utf-8').write(t)

# --- Íconos del launcher a partir del logo ---
logo = Image.open('assets/images/logo.png').convert('RGBA')
for d, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    folder = 'android/app/src/main/res/mipmap-%s' % d
    os.makedirs(folder, exist_ok=True)
    logo.resize((size, size), Image.LANCZOS).save(folder + '/ic_launcher.png')
print('Manifest e íconos listos')
PY

echo "✔ Proyecto listo."
