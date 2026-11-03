"""Read item data and extra UI string candidates without changing game assets."""
import argparse
from collections import Counter
import json
import re
import struct

import UnityPy

from survey import DEFAULT_GAME, ROOT


def aligned_string(data, offset):
    size = struct.unpack_from('<i', data, offset)[0]
    if size < 0 or offset + 4 + size > len(data):
        raise ValueError('Invalid serialized string length')
    end = offset + 4 + size
    return data[offset + 4:end].decode('utf-8'), (end + 3) & ~3


def candidates(data, start):
    # Candidate discovery only; these are never automatically translated or written back.
    result = []
    for pos in range(start, len(data) - 4, 4):
        size = struct.unpack_from('<i', data, pos)[0]
        if not 2 <= size <= 1000 or pos + 4 + size > len(data):
            continue
        try:
            text, _ = aligned_string(data, pos)
        except (UnicodeDecodeError, ValueError):
            continue
        if re.search('[A-Za-z]{2}', text) and all(c.isprintable() or c in '\n\r\t' for c in text):
            result.append(text)
    return result


def inspect(game, output):
    game, output = game.resolve(), output.resolve()
    if output == game or game in output.parents:
        raise ValueError('Output must be outside the installation')
    data_dir = game / 'Sabado Day One_Data'
    files = sorted(set(data_dir.glob('*.assets')) | set(data_dir.glob('level[0-9]*')))
    items, strings, physical, counts = [], [], [], Counter()
    for path in files:
        env = UnityPy.load(str(path))
        # Iterate only this file; resolving script references may load other files later.
        objects = list(env.objects)
        for obj in objects:
            if obj.type.name == 'Rigidbody':
                body = obj.parse_as_object()
                owner = body.m_GameObject.deref_parse_as_object()
                physical.append({'asset': path.name, 'name': owner.m_Name, 'tag': owner.m_Tag, 'layer': owner.m_Layer})
            if obj.type.name != 'MonoBehaviour':
                continue
            base = obj.parse_as_object(check_read=False)
            if not base.m_Script.path_id:
                continue
            script = base.m_Script.deref_parse_as_object()
            class_name = script.m_ClassName
            counts[class_name] += 1
            if script.m_AssemblyName not in {'Assembly-CSharp', 'Assembly-CSharp.dll'} and class_name not in {'TextMeshPro', 'TextMeshProUGUI'}:
                continue
            raw = obj.get_raw_data()
            # MonoBehaviour header: GameObject PPtr, enabled/padding, script PPtr, name.
            _, start = aligned_string(raw, 28)
            origin = {'asset': path.name, 'path_id': obj.path_id, 'class': class_name, 'name': base.m_Name}
            if class_name == 'ItemData':
                identity = struct.unpack_from('<i', raw, start)[0]
                name, pos = aligned_string(raw, start + 4)
                pos += 12  # Sprite PPtr
                maximum = struct.unpack_from('<i', raw, pos)[0]
                description, end = aligned_string(raw, pos + 4)
                if end != len(raw):
                    raise ValueError('ItemData layout changed: ' + str(origin))
                items.append(dict(origin, item_id=identity, item_name=name, max_stack=maximum, description=description))
            else:
                values = candidates(raw, start)
                if values:
                    strings.append(dict(origin, candidates=values))
    output.mkdir(parents=True, exist_ok=True)
    for name, value in [('items.json', items), ('ui-candidates.json', strings), ('physical-objects.json', physical), ('classes.json', counts)]:
        (output / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'files': len(files), 'item_records': len(items), 'unique_item_names': sorted({x['item_name'] for x in items}), 'candidate_objects': len(strings)}, ensure_ascii=True))


if __name__ == '__main__':
    from pathlib import Path
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, default=DEFAULT_GAME)
    parser.add_argument('--output', type=Path, default=ROOT / 'local/survey-extra')
    args = parser.parse_args()
    inspect(args.game, args.output)
