#!/usr/bin/env python3
import numpy as np
import pandas as pd
from pathlib import Path
from scipy import stats
import warnings
import sys

warnings.filterwarnings('ignore', category=RuntimeWarning)


# =============================================================================
# CONFIGURATION
# =============================================================================

# Condition groupings for analysis
CONDITION_MAP = {
    'nback_0a': '0-back',
    'nback_0b': '0-back', 
    'nback_1a': '1-back',
    'nback_2a': '2-back',
}

# Output column order
METRIC_COLS = [
    'n_trials', 'n_targets', 'n_nontargets',
    'hits', 'misses', 'false_alarms', 'correct_rejections',
    'hit_rate', 'fa_rate', 'd_prime', 'criterion',
    'accuracy', 'precision',
    'rt_mean', 'rt_median', 'rt_sd', 'rt_cv'
]


# =============================================================================
# SIGNAL DETECTION FUNCTIONS
# =============================================================================

def compute_sdt_metrics(hits: int, misses: int, fa: int, cr: int) -> dict:
    """
    Compute signal detection theory metrics with log-linear correction.
    
    Uses the log-linear correction (adding 0.5 to all cells) to handle
    extreme hit/FA rates that would produce infinite d'.
    
    Returns:
        dict with hit_rate, fa_rate, d_prime, criterion
    """
    n_targets = hits + misses
    n_nontargets = fa + cr
    
    # Log-linear correction (Hautus, 1995)
    # Avoids infinite d' when hit_rate=1 or fa_rate=0
    hit_rate = (hits + 0.5) / (n_targets + 1)
    fa_rate = (fa + 0.5) / (n_nontargets + 1)
    
    # d' = z(hit_rate) - z(fa_rate)
    z_hit = stats.norm.ppf(hit_rate)
    z_fa = stats.norm.ppf(fa_rate)
    d_prime = z_hit - z_fa
    
    # Criterion c = -0.5 * (z_hit + z_fa)
    # Negative c = liberal (tendency to respond)
    # Positive c = conservative (tendency to withhold)
    criterion = -0.5 * (z_hit + z_fa)
    
    # Return uncorrected rates for reporting (more interpretable)
    raw_hit_rate = hits / n_targets if n_targets > 0 else np.nan
    raw_fa_rate = fa / n_nontargets if n_nontargets > 0 else np.nan
    
    return {
        'hit_rate': raw_hit_rate,
        'fa_rate': raw_fa_rate,
        'd_prime': d_prime,
        'criterion': criterion,
    }


# =============================================================================
# TRIAL CLASSIFICATION
# =============================================================================

def classify_trials(df: pd.DataFrame) -> dict:
    """
    Classify trials into hits, misses, false alarms, correct rejections.
    
    Args:
        df: DataFrame with ExpectedResponse and ActualResponse columns
        
    Returns:
        dict with trial counts
    """
    # Determine if response was made
    if df['ActualResponse'].dtype == object:
        responded = df['ActualResponse'].notna() & (df['ActualResponse'] != '')
    else:
        responded = df['ActualResponse'].notna()
    
    expected = df['ExpectedResponse'] == 1
    
    hits = (expected & responded).sum()
    misses = (expected & ~responded).sum()
    fa = (~expected & responded).sum()
    cr = (~expected & ~responded).sum()
    
    return {
        'n_trials': len(df),
        'n_targets': int(expected.sum()),
        'n_nontargets': int((~expected).sum()),
        'hits': int(hits),
        'misses': int(misses),
        'false_alarms': int(fa),
        'correct_rejections': int(cr),
    }


def compute_accuracy_metrics(hits: int, misses: int, fa: int, cr: int) -> dict:
    """Compute accuracy and precision."""
    total = hits + misses + fa + cr
    accuracy = (hits + cr) / total if total > 0 else np.nan
    precision = hits / (hits + fa) if (hits + fa) > 0 else np.nan
    
    return {
        'accuracy': accuracy,
        'precision': precision,
    }


def compute_rt_metrics(df: pd.DataFrame) -> dict:
    """
    Compute reaction time metrics for correct responses (hits) only.
    
    This is standard practice - RTs for misses are undefined (no response),
    and RTs for false alarms may reflect different cognitive processes.
    """
    # Filter for hits: expected response AND responded AND valid RT
    expected = df['ExpectedResponse'] == 1
    
    if df['ActualResponse'].dtype == object:
        responded = df['ActualResponse'].notna() & (df['ActualResponse'] != '')
    else:
        responded = df['ActualResponse'].notna()
    
    # Get RTs for hits with valid (non-inf) values
    rt_values = df.loc[expected & responded, 'ReactionTime']
    rt_values = rt_values.replace([np.inf, -np.inf], np.nan).dropna()
    
    if len(rt_values) == 0:
        return {
            'rt_mean': np.nan,
            'rt_median': np.nan,
            'rt_sd': np.nan,
            'rt_cv': np.nan,
        }
    
    rt_mean = rt_values.mean()
    rt_sd = rt_values.std()
    
    return {
        'rt_mean': rt_mean,
        'rt_median': rt_values.median(),
        'rt_sd': rt_sd,
        'rt_cv': rt_sd / rt_mean if rt_mean > 0 else np.nan,
    }


# =============================================================================
# MAIN PROCESSING FUNCTIONS
# =============================================================================

def process_condition(df: pd.DataFrame) -> dict:
    """Process a single condition (stimulus type) and return all metrics."""
    trial_counts = classify_trials(df)
    
    sdt = compute_sdt_metrics(
        trial_counts['hits'],
        trial_counts['misses'],
        trial_counts['false_alarms'],
        trial_counts['correct_rejections']
    )
    
    acc = compute_accuracy_metrics(
        trial_counts['hits'],
        trial_counts['misses'],
        trial_counts['false_alarms'],
        trial_counts['correct_rejections']
    )
    
    rt = compute_rt_metrics(df)
    
    return {**trial_counts, **sdt, **acc, **rt}


def process_subject(filepath: Path) -> pd.DataFrame:
    """
    Process a single subject file and return metrics by condition.
    
    Returns DataFrame with conditions as rows, metrics as columns.
    """
    df = pd.read_csv(filepath)
    
    results = {}
    
    # Per stimulus type (nback_0a, nback_1a, etc.)
    for stim_type in df['StimulusType'].unique():
        subset = df[df['StimulusType'] == stim_type]
        results[stim_type] = process_condition(subset)
    
    # Collapsed by load (0-back, 1-back, 2-back)
    df['Load'] = df['StimulusType'].map(CONDITION_MAP)
    for load in df['Load'].unique():
        subset = df[df['Load'] == load]
        results[load] = process_condition(subset)
    
    # Overall
    results['Overall'] = process_condition(df)
    
    # Convert to DataFrame
    results_df = pd.DataFrame(results).T
    results_df = results_df[METRIC_COLS]  # Reorder columns
    results_df.index.name = 'Condition'
    
    return results_df


def process_all(input_dir: Path, output_dir: Path, recursive: bool = True) -> pd.DataFrame:
    """
    Process all CSV files and generate summary outputs.
    
    Args:
        input_dir: Directory containing standardized CSV files
        output_dir: Directory for output files
        recursive: Whether to search subdirectories
        
    Returns:
        Group summary DataFrame
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Find all CSV files
    pattern = '**/*.csv' if recursive else '*.csv'
    csv_files = list(input_dir.glob(pattern))
    csv_files = [f for f in csv_files if not f.name.startswith('.')]
    
    if not csv_files:
        print(f"No CSV files found in {input_dir}")
        return pd.DataFrame()
    
    print(f"Processing {len(csv_files)} files...\n")
    
    all_results = []
    
    for filepath in sorted(csv_files):
        # Include subfolder in subject ID to handle duplicates
        rel_path = filepath.relative_to(input_dir)
        if len(rel_path.parts) > 1:
            # File is in subfolder: use subfolder/filename format
            subject_id = f"{rel_path.parts[0]}_{filepath.stem}".replace('_COG', '')
        else:
            subject_id = filepath.stem.replace('_COG', '')
        
        try:
            results = process_subject(filepath)
            
            # Save individual subject file
            subj_output = output_dir / f"{subject_id}_performance.csv"
            results.to_csv(subj_output)
            
            # Add to group summary
            for condition in results.index:
                row = results.loc[condition].to_dict()
                row['SubjectID'] = subject_id
                row['Condition'] = condition
                all_results.append(row)
            
            print(f"  {subject_id}: {len(results)} conditions processed")
            
        except Exception as e:
            print(f"  {subject_id}: ERROR - {e}")
    
    # Create group summary
    if all_results:
        group_df = pd.DataFrame(all_results)
        
        # Reorder columns
        cols = ['SubjectID', 'Condition'] + METRIC_COLS
        group_df = group_df[cols]
        
        # Save group summary
        group_df.to_csv(output_dir / 'group_summary.csv', index=False)
        
        # Create pivoted summaries for key metrics
        for metric in ['d_prime', 'accuracy', 'rt_mean']:
            pivot = group_df.pivot(index='SubjectID', columns='Condition', values=metric)
            pivot.to_csv(output_dir / f'group_{metric}.csv')
        
        print(f"\nSaved outputs to {output_dir}")
        print(f"  - Individual subject files: {len(csv_files)}")
        print(f"  - group_summary.csv: Full results")
        print(f"  - group_d_prime.csv, group_accuracy.csv, group_rt_mean.csv: Pivoted")
        
        return group_df
    
    return pd.DataFrame()


# =============================================================================
# SUMMARY STATISTICS
# =============================================================================

def print_group_summary(group_df: pd.DataFrame, group_var: str = None):
    """Print summary statistics, optionally grouped."""
    
    conditions = ['0-back', '1-back', '2-back', 'Overall']
    metrics = ['d_prime', 'accuracy', 'rt_mean']
    
    print("\n" + "="*70)
    print("PERFORMANCE SUMMARY")
    print("="*70)
    
    for condition in conditions:
        subset = group_df[group_df['Condition'] == condition]
        if subset.empty:
            continue
            
        print(f"\n{condition}")
        print("-" * 40)
        
        for metric in metrics:
            vals = subset[metric].dropna()
            if len(vals) > 0:
                print(f"  {metric:12s}: {vals.mean():.3f} ± {vals.std():.3f} "
                      f"(n={len(vals)})")


# =============================================================================
# CLI
# =============================================================================

def main():
    if len(sys.argv) >= 3:
        input_dir = Path(sys.argv[1])
        output_dir = Path(sys.argv[2])
    else:
        # Default paths for testing
        input_dir = Path(__file__).parent / 'output'
        output_dir = Path(__file__).parent / 'performance'
    
    group_df = process_all(input_dir, output_dir)
    
    if not group_df.empty:
        print_group_summary(group_df)


if __name__ == '__main__':
    main()