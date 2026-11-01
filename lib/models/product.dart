part of '../main.dart';

class Product {
  const Product(
    this.name,
    this.price,
    this.detail,
    this.image, {
    this.used = false,
    this.hasPrice = true,
    this.priceEstimate = false,
    this.id = '',
    this.powerW = 0,
    this.priceSource = 'missing',
  });
  final String name;
  final String price;
  final String detail;
  final String image;
  final bool used;
  final bool hasPrice;
  final bool priceEstimate;
  final String id;
  final int powerW;
  final String priceSource;
}
