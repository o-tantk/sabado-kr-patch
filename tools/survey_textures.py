"""Inventory textures and export selected originals outside the installation (read-only)."""
import argparse
import json
from pathlib import Path

import UnityPy
from survey import DEFAULT_GAME, ROOT, sha256


def inspect(game, output):
    game, output = game.resolve(), output.resolve()
    if output == game or game in output.parents:
        raise ValueError('Output must be outside the installation')
    selected = json.loads((ROOT / 'translations/textures.json').read_text(encoding='utf-8'))
    data = game / 'Sabado Day One_Data'
    output.mkdir(parents=True, exist_ok=True)
    inventory, matches = [], []
    for path in sorted(data.glob('*.assets')):
        env = UnityPy.load(str(path))
        for obj in list(env.objects):
            if obj.type.name != 'Texture2D':
                continue
            texture = obj.parse_as_object()
            record = dict(asset=path.name, path_id=obj.path_id, texture=texture.m_Name,
                          width=texture.m_Width, height=texture.m_Height)
            inventory.append(record)
            for entry in selected:
                if entry['asset'] != path.name or entry['path_id'] != obj.path_id:
                    continue
                for field in ('texture', 'width', 'height'):
                    if entry[field] != record[field]:
                        raise ValueError('Texture identity mismatch: ' + entry['id'])
                dest = output / (entry['id'] + '-original.png')
                texture.image.save(dest)
                matches.append(dict(record, id=entry['id'], asset_sha256=sha256(path), png_sha256=sha256(dest)))
    expected = {row['id'] for row in selected}
    if {row['id'] for row in matches} != expected:
        raise ValueError('A selected texture was not found')
    for name, rows in [('inventory.json', inventory), ('selected.json', matches)]:
        (output / name).write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(textures=len(inventory), selected=len(matches))))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=DEFAULT_GAME)
    parser.add_argument('--output', type=Path, default=ROOT / 'local/survey-textures')
    args = parser.parse_args()
    inspect(args.game, args.output)
