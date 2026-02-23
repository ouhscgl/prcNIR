#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# =============================================================================
# betaGraph_compare.py
# Creates side-by-side comparison PNGs from SVG files across multiple folders.
# -----------------------------------------------------------------------------
# Developed by: zalkaposzt
# Property of: University of Oklahoma Health Sciences Center, Yabluchanskiy Lab
# Contact:     zalan-kaposzta@ou.edu
# Date:        2026
# -----------------------------------------------------------------------------
# Usage:
# python createSVGComparison.py <parent_dir> <folder1> <folder2> ... [options]
# --labels "Label1,Label2,..."   Headers    (default: folder names)
# --output <dir>                 Output dir (default: parent_dir/comparisons)
# --cell-width <px>              Cell width (default: 400)
# --cell-height <px>             Cell height(default: 300)
# --row-labels "p,q"             Row labels (default: p,q)
# =============================================================================

import argparse, re
from pathlib import Path
from io import BytesIO

try:
    import cairosvg
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Install dependencies: pip install cairosvg pillow")
    exit(1)


def svg_to_image(svg_path: Path, width: int, height: int) -> Image.Image:
    """Convert SVG to PIL Image, scaled to fit within width x height."""
    png_data = cairosvg.svg2png(url=str(svg_path))
    img = Image.open(BytesIO(png_data))
    
    img.thumbnail((width - 20, height - 20), Image.Resampling.LANCZOS)
    background = Image.new('RGB', (width, height), 'white')
    x = (width - img.width) // 2
    y = (height - img.height) // 2
    
    if img.mode == 'RGBA':
        background.paste(img, (x, y), img)
    else:
        background.paste(img, (x, y))
    
    return background


def create_placeholder(width: int, height: int) -> Image.Image:
    """Create a gray N/A placeholder."""
    img = Image.new('RGB', (width, height), '#f0f0f0')
    draw = ImageDraw.Draw(img)
    
    draw.rectangle([0, 0, width-1, height-1], outline='#cccccc')
    
    text = "N/A"
    bbox = draw.textbbox((0, 0), text)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (width - text_width) // 2
    y = (height - text_height) // 2
    draw.text((x, y), text, fill='#999999')
    
    return img


def get_font(size: int):
    font_paths = [
        "/System/Library/Fonts/Helvetica.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ]
    for fp in font_paths:
        try:
            return ImageFont.truetype(fp, size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def main():
    parser = argparse.ArgumentParser(description='Create SVG comparison figures')
    parser.add_argument('parent_dir', type=Path)
    parser.add_argument('folders', nargs='+')
    parser.add_argument('--labels', type=str, default='')
    parser.add_argument('--output', type=Path, default=None)
    parser.add_argument('--cell-width', type=int, default=400)
    parser.add_argument('--cell-height', type=int, default=300)
    parser.add_argument('--row-labels', type=str, default='p,q')
    
    args = parser.parse_args()
    
    # Parse options
    group_folders = args.folders
    group_labels = args.labels.split(',') if args.labels else [f.replace('_', ' ') for f in group_folders]
    output_dir = args.output or args.parent_dir / 'comparisons'
    row_labels = args.row_labels.split(',')
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    base_names = set()
    row_pattern = re.compile(rf'^(.+)_({"|".join(row_labels)})\.svg$')
    
    for folder in group_folders:
        folder_path = args.parent_dir / folder
        if not folder_path.is_dir():
            continue
        for svg_file in folder_path.glob('*.svg'):
            match = row_pattern.match(svg_file.name)
            if match:
                base_names.add(match.group(1))
    
    if not base_names:
        print("No matching SVG files found.")
        return
    
    print(f"Creating {len(base_names)} comparison figures...")
    
    label_height = 70
    row_label_width = 40
    n_cols = len(group_folders)
    n_rows = len(row_labels)
    total_width = row_label_width + n_cols * args.cell_width
    total_height = label_height + n_rows * args.cell_height
    
    font = get_font(14)
    
    for base in sorted(base_names):
        # Create canvas
        canvas = Image.new('RGB', (total_width, total_height), 'white')
        draw = ImageDraw.Draw(canvas)
        # Title
        bbox = draw.textbbox((0, 0), base, font=font)
        text_width = bbox[2] - bbox[0]
        draw.text((total_width // 2 - text_width // 2, 8), base, fill='black', font=font)

        # Draw column headers
        for g, label in enumerate(group_labels):
            x_center = row_label_width + g * args.cell_width + args.cell_width // 2 - 30
            bbox = draw.textbbox((0, 0), label, font=font)
            text_width = bbox[2] - bbox[0]
            draw.text((x_center - text_width // 2, 42), label, fill='black', font=font)
        
        # Draw row labels
        for r, label in enumerate(row_labels):
            y_center = label_height + r * args.cell_height + args.cell_height // 2
            bbox = draw.textbbox((0, 0), label, font=font)
            text_width = bbox[2] - bbox[0]
            text_height = bbox[3] - bbox[1]
            draw.text((row_label_width // 2 - text_width // 2, 
                      y_center - text_height // 2), label, fill='black', font=font)
        
        # Add images
        for g, folder in enumerate(group_folders):
            folder_path = args.parent_dir / folder
            
            for r, suffix in enumerate(row_labels):
                svg_file = folder_path / f"{base}_{suffix}.svg"
                x_pos = row_label_width + g * args.cell_width
                y_pos = label_height + r * args.cell_height
                
                if svg_file.is_file():
                    try:
                        cell_img = svg_to_image(svg_file, args.cell_width, args.cell_height)
                    except Exception as e:
                        print(f"  Warning: Could not convert {svg_file.name}: {e}")
                        cell_img = create_placeholder(args.cell_width, args.cell_height)
                else:
                    cell_img = create_placeholder(args.cell_width, args.cell_height)
                
                canvas.paste(cell_img, (x_pos, y_pos))
        
        # Save
        out_file = output_dir / f"{base}_comparison.png"
        canvas.save(out_file, 'PNG')
        print(f"  ✓ {base}_comparison.png")
    
    print(f"Saved {len(base_names)} comparison figures to: {output_dir}")


if __name__ == '__main__':
    main()