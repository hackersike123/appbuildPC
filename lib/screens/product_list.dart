part of '../main.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({
    super.key,
    this.componentType = 'GPU',
    this.areaId = 'hcm',
    this.onSelected,
  });
  final String componentType;
  final String areaId;
  final void Function(Product product)? onSelected;
  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  late Future<List<Product>> productsFuture;
  String query = '';
  int? maxPrice;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    productsFuture = _loadProducts();
  }

  Future<List<Product>> _loadProducts() async {
    try {
      final data = await ApiClient.instance.products(
        widget.componentType,
        query: query,
        maxPrice: maxPrice,
        areaId: widget.areaId,
      );
      return data.map((item) {
        final name = item['name'] as String;
        final price = parseApiNumber(item['price']);
        final hasPrice = price != null && price > 0;
        final priceEstimate = item['priceSource'] == 'catalog_estimate';
        final id = item['id']?.toString() ?? '';
        ApiClient.instance.productPriceSourceByName[name] =
            item['priceSource']?.toString() ?? 'missing';
        ApiClient.instance.productPowerByName[name] =
            (parseApiNumber(item['power']) ?? 0).toInt();
        ApiClient.instance.productRecommendedPsuByName[name] =
            (parseApiNumber(item['recommendedPsuW']) ?? 0).toInt();
        return Product(
          name,
          hasPrice
              ? '${(price / 1000000).toStringAsFixed(2).replaceAll('.', ',')}tr'
              : 'Chưa có giá SQL',
          '${item['socket'] ?? item['ram'] ?? item['form'] ?? 'Linh kiện'} · ${priceEstimate ? 'Giá ước tính' : 'Giá khu vực'}',
          item['type'] == 'GPU'
              ? 'assets/figma/gpu1.jpeg'
              : 'assets/figma/gpu2.png',
          hasPrice: hasPrice,
          priceEstimate: priceEstimate,
          id: id,
          powerW: (parseApiNumber(item['power']) ?? 0).toInt(),
          priceSource: item['priceSource']?.toString() ?? 'missing',
        );
      }).toList();
    } catch (error) {
      throw ApiException('Không tải được ${widget.componentType}: $error');
    }
  }

  void _refreshProducts({String? nextQuery, int? nextMaxPrice}) {
    setState(() {
      query = nextQuery ?? query;
      maxPrice = nextMaxPrice;
      productsFuture = _loadProducts();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _refreshProducts(nextQuery: value);
    });
  }

  void _selectProduct(Product product) {
    if (widget.onSelected != null) {
      if (!product.hasPrice) {
        showMessage(context, 'Chưa thể thêm sản phẩm này: chưa có giá SQL.');
        return;
      }
      widget.onSelected!(product);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CompatibilityScreen()),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Chọn ${widget.componentType}',
    subtitle: 'Giá và sản phẩm lấy từ PCBUILD API',
    back: true,
    child: SafeArea(
      child: FutureBuilder<List<Product>>(
        future: productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: mint));
          }
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Chưa tải được sản phẩm. Hãy kiểm tra backend và thử lại.',
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            );
          }
          final products = snapshot.data ?? const <Product>[];
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    TextField(
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Tìm RTX 4060, RX 7600...',
                        suffixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Tất cả'),
                          onPressed: () => _refreshProducts(nextMaxPrice: null),
                        ),
                        ActionChip(
                          label: const Text('≤ 10 triệu'),
                          onPressed: () =>
                              _refreshProducts(nextMaxPrice: 10000000),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const InfoTile(
                      text: 'Sản phẩm lấy từ SQL; giá ước tính được đánh dấu riêng.',
                      trailing: 'SQL',
                    ),
                    const SizedBox(height: 8),
                    if (products.isEmpty)
                      const CardBox(child: Text('Không có sản phẩm phù hợp.')),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => ProductCard(
                      product: products[index],
                      onTap: () => _selectProduct(products[index]),
                    ),
                    childCount: products.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
