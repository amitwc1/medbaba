import 'dart:convert';
import 'package:flutter/material.dart';

enum DrawingToolType {
  pen,
  pencil,
  highlighter,
  eraser,
  lasso,
  shape,
}

enum ShapeType {
  line,
  arrow,
  rectangle,
  circle,
  triangle,
  freeform,
}

class DrawingPoint {
  final double x;
  final double y;
  final double pressure;
  final double tilt;

  const DrawingPoint({
    required this.x,
    required this.y,
    this.pressure = 1.0,
    this.tilt = 0.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'p': pressure,
      't': tilt,
    };
  }

  factory DrawingPoint.fromJson(Map<String, dynamic> json) {
    return DrawingPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      pressure: (json['p'] as num?)?.toDouble() ?? 1.0,
      tilt: (json['t'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Offset get toOffset => Offset(x, y);

  DrawingPoint copyWith({
    double? x,
    double? y,
    double? pressure,
    double? tilt,
  }) {
    return DrawingPoint(
      x: x ?? this.x,
      y: y ?? this.y,
      pressure: pressure ?? this.pressure,
      tilt: tilt ?? this.tilt,
    );
  }
}
