import 'package:app/waypoints/icon_picker/marker_icon.dart';
import 'package:flutter/material.dart';

/// Sample built-in categories for tests of the «Иконка» sheet and dialog.
const sampleCategories = <IconCategory>[
  IconCategory(
    id: 'marker',
    title: 'МЕТКА',
    icons: [
      MarkerIcon(id: 'marker-default', label: 'Default', icon: Icons.place),
      MarkerIcon(id: 'marker-star', label: 'Star', icon: Icons.star),
    ],
  ),
  IconCategory(
    id: 'tourism',
    title: 'ТУРИЗМ',
    icons: [
      MarkerIcon(id: 'tourism-camp', label: 'Camp', icon: Icons.cabin),
      MarkerIcon(id: 'tourism-view', label: 'Viewpoint', icon: Icons.landscape),
      MarkerIcon(id: 'tourism-museum', label: 'Museum', icon: Icons.museum),
    ],
  ),
  IconCategory(
    id: 'transport',
    title: 'ТРАНСПОРТ',
    icons: [
      MarkerIcon(id: 'transport-parking', label: 'Parking', icon: Icons.local_parking),
      MarkerIcon(id: 'transport-fuel', label: 'Fuel', icon: Icons.local_gas_station),
    ],
  ),
  IconCategory(
    id: 'food',
    title: 'ПИТАНИЕ',
    icons: [
      MarkerIcon(id: 'food-cafe', label: 'Cafe', icon: Icons.local_cafe),
      MarkerIcon(id: 'food-restaurant', label: 'Restaurant', icon: Icons.restaurant),
    ],
  ),
  IconCategory(
    id: 'structures',
    title: 'СООРУЖЕНИЯ',
    icons: [
      MarkerIcon(id: 'struct-manmade', label: 'Man made'),
      MarkerIcon(id: 'struct-bunker', label: 'Bunker', icon: Icons.shield),
      MarkerIcon(id: 'struct-checkpoint', label: 'Checkpoint', icon: Icons.security),
      MarkerIcon(id: 'struct-chimney', label: 'Chimney', icon: Icons.factory),
      MarkerIcon(id: 'struct-crane', label: 'Crane', icon: Icons.precision_manufacturing),
      MarkerIcon(id: 'struct-military', label: 'Military', icon: Icons.military_tech),
      MarkerIcon(id: 'struct-mine', label: 'Mine', icon: Icons.construction),
    ],
  ),
  IconCategory(
    id: 'nature',
    title: 'ПРИРОДА',
    icons: [
      MarkerIcon(id: 'nature-tree', label: 'Tree', icon: Icons.park),
      MarkerIcon(id: 'nature-water', label: 'Water', icon: Icons.water),
    ],
  ),
];
