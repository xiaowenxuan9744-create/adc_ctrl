"""Convert FEC设计文档.docx to Markdown with proper image references."""
import zipfile, os, sys
from xml.etree import ElementTree as ET

def main(docx_path, img_dir_name, out_path):
    W = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
    WP = '{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}'
    A = '{http://schemas.openxmlformats.org/drawingml/2006/main}'
    R = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}'
    RELS_NS = '{http://schemas.openxmlformats.org/package/2006/relationships}'

    with zipfile.ZipFile(docx_path) as z:

        # --- rId → image filename ---
        rels = ET.parse(z.open('word/_rels/document.xml.rels'))
        rid_to_img = {}
        for rel in rels.getroot():
            if 'image' in (rel.get('Type') or ''):
                rid_to_img[rel.get('Id')] = os.path.basename(rel.get('Target'))

        # --- style name lookup (styleId → name) ---
        try:
            styles_tree = ET.parse(z.open('word/styles.xml'))
            style_names = {}
            for s in styles_tree.getroot().findall(f'{W}style'):
                sid = s.get(f'{W}styleId')
                name_el = s.find(f'{W}name')
                if sid and name_el is not None:
                    style_names[sid] = name_el.get(f'{W}val', '')
        except Exception:
            style_names = {}

        # --- parse document ---
        doc = ET.parse(z.open('word/document.xml'))
        body = doc.getroot().find(f'{W}body')

        output = []
        # Track table state
        in_table = False

        for elem in body:
            tag = elem.tag[len(W):] if elem.tag.startswith(W) else elem.tag

            if tag == 'p':
                in_table = False
                para = parse_paragraph(elem, rid_to_img, style_names, W, A, R, WP, img_dir_name)
                if para is not None:
                    output.extend(para)

            elif tag == 'tbl':
                in_table = True
                table_md = parse_table(elem, W, A, R, rid_to_img, img_dir_name)
                if table_md:
                    output.extend(table_md)
                    output.append('')

            elif tag == 'sectPr':
                pass

        result = '\n'.join(output)
        with open(out_path, 'w', encoding='utf-8', errors='replace') as f:
            f.write(result)
        print(f'Written {len(result)} chars to {out_path}')


def parse_paragraph(elem, rid_to_img, style_names, W, A, R, WP, img_dir_name):
    # Check for image(s) — a paragraph may contain multiple drawings
    blips = list(elem.iter(f'{A}blip'))
    img_rIds = []
    for blip in blips:
        embed = blip.get(f'{R}embed')
        if embed and embed in rid_to_img:
            img_rIds.append(embed)

    if img_rIds:
        lines = []
        for img_rId in img_rIds:
            img_file = rid_to_img[img_rId]
            # Try to extract alt text from nearest docPr
            alt = ''
            for docPr in elem.iter(f'{WP}docPr'):
                descr = docPr.get('descr', '')
                if descr:
                    alt = descr
                    break
            lines.append(f'![{alt}]({img_dir_name}/{img_file})')
            lines.append('')
        return lines

    # Get paragraph style and check if heading
    pPr = elem.find(f'{W}pPr')
    heading_level = 0
    if pPr is not None:
        # Check outline level first
        outline_lvl = pPr.find(f'{W}outlineLvl')
        if outline_lvl is not None:
            heading_level = int(outline_lvl.get(f'{W}val', '0')) + 1
        else:
            # Check pStyle for heading styles
            pStyle = pPr.find(f'{W}pStyle')
            if pStyle is not None:
                sid = pStyle.get(f'{W}val', '')
                name = style_names.get(sid, sid)
                if 'heading' in name.lower() or name.lower().startswith('toc'):
                    # Extract heading number
                    for c in name:
                        if c.isdigit():
                            heading_level = int(c)
                            break
                elif sid.isdigit():
                    heading_level = int(sid)

    # Collect text with formatting
    parts = []
    for p_elem in elem.iter(f'{W}p'):
        pass  # skip to runs below

    # Process runs
    runs = elem.findall(f'{W}r') + elem.findall(f'{W}hyperlink')

    if not runs:
        # Try direct text extraction for simple paragraphs
        texts = [t.text or '' for t in elem.iter(f'{W}t')]
        raw = ''.join(texts).strip()
        if not raw:
            return ['']
        if heading_level > 0:
            return [f'{"#" * heading_level} {raw}', '']
        return [raw, '']

    for r in runs:
        is_hyperlink = r.tag.endswith('hyperlink')
        run_texts = [t.text or '' for t in r.iter(f'{W}t')]
        text = ''.join(run_texts)
        if not text:
            continue

        rPr = r.find(f'{W}rPr')
        if rPr is not None:
            is_bold = rPr.find(f'{W}b') is not None and rPr.find(f'{W}b').get(f'{W}val') != '0'
            is_italic = rPr.find(f'{W}i') is not None and rPr.find(f'{W}i').get(f'{W}val') != '0'
            if is_bold and is_italic:
                text = f'***{text}***'
            elif is_bold:
                text = f'**{text}**'
            elif is_italic:
                text = f'*{text}*'
        parts.append(text)

    raw = ''.join(parts).strip()
    if not raw:
        return ['']

    if heading_level > 0:
        return [f'{"#" * heading_level} {raw}', '']
    return [raw, '']


def parse_table(tbl, W, A, R, rid_to_img, img_dir_name):
    lines = []
    rows = tbl.findall(f'{W}tr')
    if not rows:
        return lines

    col_count = 0
    for row in rows:
        cells = []
        for cell in row.findall(f'{W}tc'):
            # Check for image in cell
            drawings = cell.findall(f'.//{W}drawing')
            if drawings:
                img_rId = None
                for blip in cell.iter(f'{A}blip'):
                    embed = blip.get(f'{R}embed')
                    if embed and embed in rid_to_img:
                        img_rId = embed
                        break
                if img_rId:
                    img_file = rid_to_img[img_rId]
                    cells.append(f'![image]({img_dir_name}/{img_file})')
                else:
                    cells.append('')
            else:
                texts = [t.text or '' for t in cell.iter(f'{W}t')]
                cell_text = ' '.join(''.join(texts).split()).strip()
                cells.append(cell_text)

        if cells:
            col_count = max(col_count, len(cells))
            lines.append('| ' + ' | '.join(cells) + ' |')

    if lines:
        # Insert header separator after first row
        sep = '|' + '|'.join([' --- ' for _ in range(col_count)]) + '|'
        lines.insert(1, sep)

    return lines


if __name__ == '__main__':
    docx = sys.argv[1] if len(sys.argv) > 1 else 'input.docx'
    img_dir = sys.argv[2] if len(sys.argv) > 2 else 'images'
    out = sys.argv[3] if len(sys.argv) > 3 else 'output.md'
    main(docx, img_dir, out)
