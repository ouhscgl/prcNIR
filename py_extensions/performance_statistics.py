#!/usr/bin/env python3
"""
N-back Performance Statistical Analysis & Visualization
========================================================
Analyzes group differences in N-back performance using Mixed ANOVA
and pairwise comparisons with FDR correction.

Input: group_summary.csv from extract_performance.py

Output:
    - Statistical results (ANOVA, pairwise comparisons)
    - Bar plots per condition
    - Grand average plots
    - d' trajectory plot
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
from pathlib import Path
from scipy import stats
from itertools import combinations
import warnings
import sys

warnings.filterwarnings('ignore')


# =============================================================================
# CONFIGURATION
# =============================================================================

# Group display order and labels
GROUP_ORDER = ['healthy_controls', 'normal_performers', 'low_performers']
GROUP_LABELS = {
    'healthy_controls': 'Healthy Controls',
    'normal_performers': 'Normal Performers', 
    'low_performers': 'Low Performers',
}

# Condition display order
CONDITION_ORDER = ['nback_0a', 'nback_1a', 'nback_0b', 'nback_2a']
CONDITION_LABELS = {
    'nback_0a': '0-back A',
    'nback_1a': '1-back',
    'nback_0b': '0-back B',
    'nback_2a': '2-back',
    'grand_average': 'Grand Avg',
}

# Placeholder colors (replace with your preferred colors)
# Format: RGB tuples normalized to 0-1
GROUP_COLORS = {
    'healthy_controls': (0.467, 0.867, 0.467),    # Light green
    'normal_performers': (0.886, 0.698, 0.447),   # Orange/tan
    'low_performers': (0.753, 0.502, 0.494),      # Muted red/pink
}

# Metrics to analyze
METRICS = {
    'd_prime': {'label': "d'", 'ylabel': "d' (sensitivity)"},
    'rt_mean': {'label': 'Mean RT', 'ylabel': 'Reaction Time (s)'},
}


# =============================================================================
# DATA LOADING
# =============================================================================

def load_and_prepare_data(filepath: Path) -> pd.DataFrame:
    """Load group_summary.csv and extract group from SubjectID."""
    df = pd.read_csv(filepath)
    
    # Extract group from SubjectID prefix
    def extract_group(subject_id):
        for group in GROUP_ORDER:
            if subject_id.startswith(group):
                return group
        return 'unknown'
    
    df['Group'] = df['SubjectID'].apply(extract_group)
    
    # Extract clean subject ID (without group prefix)
    def clean_subject_id(subject_id):
        for group in GROUP_ORDER:
            if subject_id.startswith(group + '_'):
                return subject_id[len(group) + 1:]
        return subject_id
    
    df['Subject'] = df['SubjectID'].apply(clean_subject_id)
    
    # Filter to only known groups and specified conditions
    df = df[df['Group'].isin(GROUP_ORDER)]
    df = df[df['Condition'].isin(CONDITION_ORDER)]
    
    return df


# =============================================================================
# STATISTICAL ANALYSIS
# =============================================================================

def mixed_anova(df: pd.DataFrame, metric: str) -> dict:
    """
    Perform mixed ANOVA (Group × Condition).
    
    Between-subjects: Group
    Within-subjects: Condition
    
    Returns dict with F-values, p-values for main effects and interaction.
    """
    try:
        import pingouin as pg
        
        result = pg.mixed_anova(
            data=df,
            dv=metric,
            within='Condition',
            between='Group',
            subject='Subject'
        )
        
        return {
            'Group': {
                'F': result.loc[result['Source'] == 'Group', 'F'].values[0],
                'p': result.loc[result['Source'] == 'Group', 'p-unc'].values[0],
                'np2': result.loc[result['Source'] == 'Group', 'np2'].values[0],
            },
            'Condition': {
                'F': result.loc[result['Source'] == 'Condition', 'F'].values[0],
                'p': result.loc[result['Source'] == 'Condition', 'p-unc'].values[0],
                'np2': result.loc[result['Source'] == 'Condition', 'np2'].values[0],
            },
            'Interaction': {
                'F': result.loc[result['Source'] == 'Interaction', 'F'].values[0],
                'p': result.loc[result['Source'] == 'Interaction', 'p-unc'].values[0],
                'np2': result.loc[result['Source'] == 'Interaction', 'np2'].values[0],
            },
        }
    except ImportError:
        print("  Warning: pingouin not installed, skipping mixed ANOVA")
        print("  Install with: pip install pingouin")
        return None
    except Exception as e:
        print(f"  Warning: Mixed ANOVA failed - {e}")
        return None


def cohens_d(group1: np.ndarray, group2: np.ndarray) -> float:
    """Calculate Cohen's d effect size."""
    n1, n2 = len(group1), len(group2)
    var1, var2 = group1.var(ddof=1), group2.var(ddof=1)
    
    # Pooled standard deviation
    pooled_std = np.sqrt(((n1 - 1) * var1 + (n2 - 1) * var2) / (n1 + n2 - 2))
    
    if pooled_std == 0:
        return 0.0
    
    return (group1.mean() - group2.mean()) / pooled_std


def fdr_correction(p_values: list) -> list:
    """Benjamini-Hochberg FDR correction."""
    n = len(p_values)
    if n == 0:
        return []
    
    # Sort p-values and track original indices
    sorted_indices = np.argsort(p_values)
    sorted_p = np.array(p_values)[sorted_indices]
    
    # Calculate adjusted p-values
    adjusted = np.zeros(n)
    for i, p in enumerate(sorted_p):
        adjusted[i] = p * n / (i + 1)
    
    # Ensure monotonicity (each q >= previous q)
    for i in range(n - 2, -1, -1):
        adjusted[i] = min(adjusted[i], adjusted[i + 1])
    
    # Clip to [0, 1]
    adjusted = np.clip(adjusted, 0, 1)
    
    # Restore original order
    result = np.zeros(n)
    result[sorted_indices] = adjusted
    
    return result.tolist()


def pairwise_comparisons(df: pd.DataFrame, metric: str) -> pd.DataFrame:
    """
    Perform pairwise t-tests between groups for each condition.
    
    Returns DataFrame with all comparisons, uncorrected p, FDR-corrected q, and Cohen's d.
    """
    results = []
    
    for condition in CONDITION_ORDER:
        cond_data = df[df['Condition'] == condition]
        
        for g1, g2 in combinations(GROUP_ORDER, 2):
            vals1 = cond_data.loc[cond_data['Group'] == g1, metric].dropna().values
            vals2 = cond_data.loc[cond_data['Group'] == g2, metric].dropna().values
            
            if len(vals1) < 2 or len(vals2) < 2:
                continue
            
            t_stat, p_val = stats.ttest_ind(vals1, vals2)
            d = cohens_d(vals1, vals2)
            
            results.append({
                'Condition': condition,
                'Group1': g1,
                'Group2': g2,
                'Mean1': vals1.mean(),
                'SD1': vals1.std(ddof=1),
                'n1': len(vals1),
                'Mean2': vals2.mean(),
                'SD2': vals2.std(ddof=1),
                'n2': len(vals2),
                't': t_stat,
                'p': p_val,
                'd': d,
            })
    
    if not results:
        return pd.DataFrame()
    
    results_df = pd.DataFrame(results)
    
    # Apply FDR correction across all comparisons
    results_df['q'] = fdr_correction(results_df['p'].tolist())
    
    return results_df


def grand_average_pairwise_comparisons(df: pd.DataFrame, metric: str) -> pd.DataFrame:
    """
    Perform pairwise t-tests between groups on grand average (mean across conditions).
    
    Returns DataFrame with all comparisons, uncorrected p, FDR-corrected q, and Cohen's d.
    """
    # Calculate grand average per subject (across all conditions)
    grand_avg = df.groupby(['Subject', 'Group'])[metric].mean().reset_index()
    
    results = []
    
    for g1, g2 in combinations(GROUP_ORDER, 2):
        vals1 = grand_avg.loc[grand_avg['Group'] == g1, metric].dropna().values
        vals2 = grand_avg.loc[grand_avg['Group'] == g2, metric].dropna().values
        
        if len(vals1) < 2 or len(vals2) < 2:
            continue
        
        t_stat, p_val = stats.ttest_ind(vals1, vals2)
        d = cohens_d(vals1, vals2)
        
        results.append({
            'Condition': 'grand_average',
            'Group1': g1,
            'Group2': g2,
            'Mean1': vals1.mean(),
            'SD1': vals1.std(ddof=1),
            'n1': len(vals1),
            'Mean2': vals2.mean(),
            'SD2': vals2.std(ddof=1),
            'n2': len(vals2),
            't': t_stat,
            'p': p_val,
            'd': d,
        })
    
    if not results:
        return pd.DataFrame()
    
    results_df = pd.DataFrame(results)
    
    # Apply FDR correction across grand average comparisons
    results_df['q'] = fdr_correction(results_df['p'].tolist())
    
    return results_df


def get_group_stats(df: pd.DataFrame, metric: str) -> pd.DataFrame:
    """Get descriptive statistics per group × condition."""
    stats_list = []
    
    for condition in CONDITION_ORDER:
        for group in GROUP_ORDER:
            subset = df[(df['Condition'] == condition) & (df['Group'] == group)]
            values = subset[metric].dropna()
            
            stats_list.append({
                'Condition': condition,
                'Group': group,
                'Mean': values.mean(),
                'SD': values.std(ddof=1),
                'SEM': values.std(ddof=1) / np.sqrt(len(values)) if len(values) > 0 else np.nan,
                'n': len(values),
            })
    
    return pd.DataFrame(stats_list)


# =============================================================================
# VISUALIZATION
# =============================================================================

def add_significance_bracket(ax, x1, x2, y, p_val, height=0.02):
    """Add significance bracket between two x positions."""
    # Determine significance stars
    if p_val < 0.001:
        sig_text = '***'
    elif p_val < 0.01:
        sig_text = '**'
    elif p_val < 0.05:
        sig_text = '*'
    else:
        return  # No bracket for non-significant
    
    # Draw bracket
    y_bracket = y
    bracket_height = height * (ax.get_ylim()[1] - ax.get_ylim()[0])
    
    ax.plot([x1, x1, x2, x2], 
            [y_bracket, y_bracket + bracket_height, y_bracket + bracket_height, y_bracket],
            'k-', linewidth=1)
    
    # Add stars
    ax.text((x1 + x2) / 2, y_bracket + bracket_height, sig_text,
            ha='center', va='bottom', fontsize=11, fontweight='bold')


def plot_condition_bars(df: pd.DataFrame, metric: str, pairwise_df: pd.DataFrame,
                        output_dir: Path):
    """
    Create bar plot with all conditions and groups.
    4 condition clusters, 3 bars each.
    """
    fig, ax = plt.subplots(figsize=(12, 6))
    
    stats_df = get_group_stats(df, metric)
    
    n_conditions = len(CONDITION_ORDER)
    n_groups = len(GROUP_ORDER)
    bar_width = 0.25
    
    # X positions for condition clusters
    x_base = np.arange(n_conditions)
    
    # Plot bars for each group
    for i, group in enumerate(GROUP_ORDER):
        group_stats = stats_df[stats_df['Group'] == group]
        x_pos = x_base + (i - 1) * bar_width  # Center the middle bar
        
        means = [group_stats[group_stats['Condition'] == c]['Mean'].values[0] 
                 for c in CONDITION_ORDER]
        sems = [group_stats[group_stats['Condition'] == c]['SEM'].values[0] 
                for c in CONDITION_ORDER]
        
        bars = ax.bar(x_pos, means, bar_width, 
                      label=GROUP_LABELS[group],
                      color=GROUP_COLORS[group],
                      edgecolor='white',
                      linewidth=1)
        
        ax.errorbar(x_pos, means, yerr=sems, fmt='none', 
                    color='black', capsize=3, linewidth=1)
    
    # Add significance brackets
    if not pairwise_df.empty:
        metric_comparisons = pairwise_df[pairwise_df['q'] < 0.05]
        
        for _, row in metric_comparisons.iterrows():
            cond_idx = CONDITION_ORDER.index(row['Condition'])
            g1_idx = GROUP_ORDER.index(row['Group1'])
            g2_idx = GROUP_ORDER.index(row['Group2'])
            
            x1 = cond_idx + (g1_idx - 1) * bar_width
            x2 = cond_idx + (g2_idx - 1) * bar_width
            
            # Get max height in this condition for bracket placement
            cond_stats = stats_df[stats_df['Condition'] == row['Condition']]
            max_y = (cond_stats['Mean'] + cond_stats['SEM']).max()
            
            # Stagger brackets if multiple comparisons
            bracket_offset = 0.05 * (ax.get_ylim()[1] - ax.get_ylim()[0]) if ax.get_ylim()[1] > 0 else 0.1
            
            add_significance_bracket(ax, x1, x2, max_y + bracket_offset, row['q'])
    
    # Formatting
    ax.set_xticks(x_base)
    ax.set_xticklabels([CONDITION_LABELS[c] for c in CONDITION_ORDER], fontsize=12)
    ax.set_ylabel(METRICS[metric]['ylabel'], fontsize=12, fontweight='bold')
    ax.set_title(f"{METRICS[metric]['label']} by Condition and Group", 
                 fontsize=14, fontweight='bold')
    ax.legend(loc='upper right', frameon=False)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    
    # Adjust y-axis to make room for brackets
    ymin, ymax = ax.get_ylim()
    ax.set_ylim(ymin, ymax * 1.15)
    
    plt.tight_layout()
    plt.savefig(output_dir / f'barplot_{metric}.png', dpi=300, bbox_inches='tight')
    plt.savefig(output_dir / f'barplot_{metric}.svg', bbox_inches='tight')
    plt.close()


def plot_grand_average(df: pd.DataFrame, metric: str, output_dir: Path):
    """
    Create grand average bar plot with individual data points.
    """
    fig, ax = plt.subplots(figsize=(8, 6))
    
    # Calculate grand average per subject (across all conditions)
    grand_avg = df.groupby(['Subject', 'Group'])[metric].mean().reset_index()
    
    # Calculate group statistics
    group_stats = []
    for group in GROUP_ORDER:
        values = grand_avg[grand_avg['Group'] == group][metric].dropna()
        group_stats.append({
            'Group': group,
            'Mean': values.mean(),
            'SEM': values.std(ddof=1) / np.sqrt(len(values)),
            'values': values.values,
        })
    
    x_pos = np.arange(len(GROUP_ORDER))
    
    # Plot bars
    for i, gs in enumerate(group_stats):
        ax.bar(i, gs['Mean'], 0.6,
               color=GROUP_COLORS[gs['Group']],
               edgecolor='white',
               linewidth=1)
        ax.errorbar(i, gs['Mean'], yerr=gs['SEM'], fmt='none',
                    color='black', capsize=4, linewidth=1.5)
        
        # Individual data points with jitter
        jitter = np.random.uniform(-0.15, 0.15, len(gs['values']))
        ax.scatter(i + jitter, gs['values'], 
                   color=np.array(GROUP_COLORS[gs['Group']]) * 0.7,
                   edgecolor='black', s=50, alpha=0.7, zorder=3)
    
    # Pairwise comparisons for grand average
    p_values = []
    comparisons = list(combinations(range(len(GROUP_ORDER)), 2))
    
    for i, j in comparisons:
        vals1 = group_stats[i]['values']
        vals2 = group_stats[j]['values']
        if len(vals1) >= 2 and len(vals2) >= 2:
            _, p = stats.ttest_ind(vals1, vals2)
            p_values.append((i, j, p))
    
    # Add significance brackets
    if p_values:
        q_values = fdr_correction([p[2] for p in p_values])
        max_y = max([gs['Mean'] + gs['SEM'] for gs in group_stats])
        
        bracket_y = max_y * 1.05
        for (i, j, p), q in zip(p_values, q_values):
            if q < 0.05:
                add_significance_bracket(ax, i, j, bracket_y, q)
                bracket_y += 0.08 * (ax.get_ylim()[1] - ax.get_ylim()[0])
    
    # Formatting
    ax.set_xticks(x_pos)
    ax.set_xticklabels([GROUP_LABELS[g] for g in GROUP_ORDER], fontsize=11)
    ax.set_ylabel(METRICS[metric]['ylabel'], fontsize=12, fontweight='bold')
    ax.set_title(f"Grand Average {METRICS[metric]['label']}", 
                 fontsize=14, fontweight='bold')
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    
    # Adjust y-axis
    ymin, ymax = ax.get_ylim()
    ax.set_ylim(ymin, ymax * 1.2)
    
    plt.tight_layout()
    plt.savefig(output_dir / f'grand_average_{metric}.png', dpi=300, bbox_inches='tight')
    plt.savefig(output_dir / f'grand_average_{metric}.svg', bbox_inches='tight')
    plt.close()


def plot_trajectory(df: pd.DataFrame, metric: str, output_dir: Path):
    """
    Create trajectory plot showing metric across conditions by group.
    """
    fig, ax = plt.subplots(figsize=(8, 6))
    
    stats_df = get_group_stats(df, metric)
    markers = ['o', 's', '^']
    
    for i, group in enumerate(GROUP_ORDER):
        group_stats = stats_df[stats_df['Group'] == group]
        
        means = [group_stats[group_stats['Condition'] == c]['Mean'].values[0] 
                 for c in CONDITION_ORDER]
        sems = [group_stats[group_stats['Condition'] == c]['SEM'].values[0] 
                for c in CONDITION_ORDER]
        
        x = np.arange(len(CONDITION_ORDER))
        
        ax.errorbar(x, means, yerr=sems,
                    marker=markers[i], markersize=10,
                    color=GROUP_COLORS[group],
                    markerfacecolor=GROUP_COLORS[group],
                    markeredgecolor='white',
                    linewidth=2, capsize=5,
                    label=GROUP_LABELS[group])
    
    # Formatting
    ax.set_xticks(np.arange(len(CONDITION_ORDER)))
    ax.set_xticklabels([CONDITION_LABELS[c] for c in CONDITION_ORDER], fontsize=11)
    ax.set_xlabel('Condition', fontsize=12, fontweight='bold')
    ax.set_ylabel(METRICS[metric]['ylabel'], fontsize=12, fontweight='bold')
    ax.set_title(f"{METRICS[metric]['label']} Trajectory Across Conditions",
                 fontsize=14, fontweight='bold')
    ax.legend(loc='best', frameon=False)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.grid(True, alpha=0.3, linewidth=0.5)
    
    plt.tight_layout()
    plt.savefig(output_dir / f'trajectory_{metric}.png', dpi=300, bbox_inches='tight')
    plt.savefig(output_dir / f'trajectory_{metric}.svg', bbox_inches='tight')
    plt.close()


# =============================================================================
# REPORTING
# =============================================================================

def print_results(metric: str, anova_result: dict, pairwise_df: pd.DataFrame):
    """Print formatted statistical results."""
    print(f"\n{'='*70}")
    print(f"{METRICS[metric]['label'].upper()}")
    print('='*70)
    
    # Mixed ANOVA results
    if anova_result:
        print("\nMixed ANOVA (Group × Condition):")
        print("-" * 50)
        for effect, stats in anova_result.items():
            sig = '***' if stats['p'] < 0.001 else '**' if stats['p'] < 0.01 else '*' if stats['p'] < 0.05 else ''
            print(f"  {effect:12s}: F = {stats['F']:6.2f}, p = {stats['p']:.4f}{sig}, ηp² = {stats['np2']:.3f}")
    
    # Pairwise comparisons
    if not pairwise_df.empty:
        print("\nPairwise Comparisons (FDR-corrected):")
        print("-" * 50)
        print(f"{'Condition':<12} {'Comparison':<35} {'t':>7} {'p':>8} {'q':>8} {'d':>7}")
        print("-" * 80)
        
        for _, row in pairwise_df.iterrows():
            g1_short = GROUP_LABELS[row['Group1']].split()[0]
            g2_short = GROUP_LABELS[row['Group2']].split()[0]
            comparison = f"{g1_short} vs {g2_short}"
            
            sig = '***' if row['q'] < 0.001 else '**' if row['q'] < 0.01 else '*' if row['q'] < 0.05 else ''
            
            print(f"{CONDITION_LABELS[row['Condition']]:<12} {comparison:<35} "
                  f"{row['t']:>7.2f} {row['p']:>8.4f} {row['q']:>7.4f}{sig} {row['d']:>7.2f}")


def save_results(metric: str, anova_result: dict, pairwise_df: pd.DataFrame, 
                 stats_df: pd.DataFrame, output_dir: Path):
    """Save statistical results to CSV files."""
    # Save pairwise comparisons
    if not pairwise_df.empty:
        pairwise_df.to_csv(output_dir / f'pairwise_{metric}.csv', index=False)
    
    # Save descriptive statistics
    stats_df.to_csv(output_dir / f'descriptives_{metric}.csv', index=False)
    
    # Save ANOVA results
    if anova_result:
        anova_df = pd.DataFrame(anova_result).T
        anova_df.index.name = 'Effect'
        anova_df.to_csv(output_dir / f'anova_{metric}.csv')


# =============================================================================
# MAIN
# =============================================================================

def main():
    if len(sys.argv) >= 3:
        input_path = Path(sys.argv[1])
        output_dir = Path(sys.argv[2])
    else:
        input_path = Path(__file__).parent / 'performance' / 'group_summary.csv'
        output_dir = Path(__file__).parent / 'figures'
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("Loading data...")
    df = load_and_prepare_data(input_path)
    
    print(f"Found {df['Subject'].nunique()} subjects across {df['Group'].nunique()} groups")
    for group in GROUP_ORDER:
        n = df[df['Group'] == group]['Subject'].nunique()
        print(f"  {GROUP_LABELS[group]}: n={n}")
    
    # Analyze each metric
    for metric in METRICS:
        print(f"\nAnalyzing {METRICS[metric]['label']}...")
        
        # Statistics
        anova_result = mixed_anova(df, metric)
        pairwise_df = pairwise_comparisons(df, metric)
        grand_avg_pairwise_df = grand_average_pairwise_comparisons(df, metric)
        stats_df = get_group_stats(df, metric)
        
        # Combine per-condition and grand average pairwise comparisons
        if not grand_avg_pairwise_df.empty:
            combined_pairwise_df = pd.concat([pairwise_df, grand_avg_pairwise_df], 
                                              ignore_index=True)
        else:
            combined_pairwise_df = pairwise_df
        
        # Print results (including grand average)
        print_results(metric, anova_result, combined_pairwise_df)
        
        # Save results (with grand average included)
        save_results(metric, anova_result, combined_pairwise_df, stats_df, output_dir)
        
        # Generate plots
        print(f"  Generating plots...")
        plot_condition_bars(df, metric, pairwise_df, output_dir)
        plot_grand_average(df, metric, output_dir)
        plot_trajectory(df, metric, output_dir)
    
    print(f"\nAll outputs saved to {output_dir}")

if __name__ == '__main__':
    main()