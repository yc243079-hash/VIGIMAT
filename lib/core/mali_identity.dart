import 'package:flutter/material.dart';

import 'vigimat_brand.dart';

class MaliIdentity extends StatelessWidget {
  const MaliIdentity({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F6FA),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: VigimatColors.border),
    ),
    child: Row(
      children: [
        Semantics(
          label: 'Drapeau du Mali',
          image: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: const SizedBox(
              width: 42,
              height: 27,
              child: Row(
                children: [
                  Expanded(child: ColoredBox(color: Color(0xFF14B53A))),
                  Expanded(child: ColoredBox(color: Color(0xFFFCD116))),
                  Expanded(child: ColoredBox(color: Color(0xFFCE1126))),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'UN PEUPLE – UN BUT – UNE FOI',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: VigimatColors.navy,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    ),
  );
}
