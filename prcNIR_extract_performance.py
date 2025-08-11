"""
Cognitive data output processor for the e-prime n-back paradigm v3.0
Ver. 2.4 (Optimized for UTF-8-sig encoded CSV files)
"""
import pandas as pd
import glob
from pathlib import Path

class CognitiveDataProcessor:
    def __init__(self, load_path, save_path):
        self.load_path = Path(load_path)
        self.save_path = Path(save_path)
        self.metrics = ['hits', 'false neg', 'false neg rate', 'false pos', 'false pos rate', 
                       'total positives', 'total negatives', 'mean', '50%', 'min', 'max', 'std']
        self.labels = ['entire', '0back1', '1back1', '0back2', '2back1']
        self.results_df_dict = {label: pd.DataFrame(columns=self.metrics) for label in self.labels}

    def load_data(self):
        """
        Load all CSV files from the specified directory.
        Primarily tries utf-8-sig encoding, with fallbacks.
        """
        file_list = list(self.load_path.glob('*.csv'))
        data_name_pairs = []
        
        for f in file_list:
            # Try encodings with utf-8-sig as primary
            for encoding in ['utf-8-sig', 'utf-8', 'cp1252', 'latin1', 'utf-16']:
                try:
                    df = pd.read_csv(f, encoding=encoding)
                    data_name_pairs.append((df, f.stem[:9]))
                    print(f"Successfully loaded {f.name} using {encoding} encoding")
                    break  # Break the encoding loop if successful
                except UnicodeError:
                    # Try next encoding
                    continue
                except Exception as e:
                    print(f"Error loading {f.name}: {str(e)}")
                    break  # Break if it's not an encoding issue
            else:
                # This runs if the for loop completed without a break
                print(f"Failed to load {f.name} with any encoding. Skipping file.")
        
        return data_name_pairs
        
    def validate_dataframe(self, df):
        """
        Validates that a dataframe has all required columns.
        Returns True if valid, False if any required column is missing.
        """
        required_columns = {
            'ResponseType',
            'Procedure',
            'Letter1.RT',
            'Letter2.RT',
            'Letter3.RT',
            'Letter4.RT'
        }
        
        missing_columns = required_columns - set(df.columns)
        
        if missing_columns:
            print(f"Warning: Missing columns in dataframe: {', '.join(missing_columns)}")
            return False
        
        return True

    def process_response_metrics(self, data):
        """Process response metrics for each data frame."""
        storage = {metric: [0] * len(self.labels) for metric in self.metrics[:7]}
        
        for idx, row in data.iterrows():
            if not row['ResponseType']:
                print(f'No response value at {idx}')
                continue
                
            i = int(row['Procedure'][-1])
            response_type = row['ResponseType']
            
            # Update counters based on response type
            if any(rt in response_type for rt in ['Correct-NoResponse', 'Incorrect-FalseAlarm']):
                storage['total negatives'][i] += 1
                storage['total negatives'][0] += 1
            if any(rt in response_type for rt in ['Correct-Hit', 'Incorrect-NoResponse']):
                storage['total positives'][i] += 1
                storage['total positives'][0] += 1
            if 'Correct-Hit' in response_type:
                storage['hits'][i] += 1
                storage['hits'][0] += 1
            if 'Incorrect-FalseAlarm' in response_type:
                storage['false pos'][i] += 1
                storage['false pos'][0] += 1
            if 'Incorrect-NoResponse' in response_type:
                storage['false neg'][i] += 1
                storage['false neg'][0] += 1

        # Calculate rates, avoiding division by zero
        for i in range(5):
            # Handle division by zero for false negative rate
            if storage['total positives'][i] == 0:
                storage['false neg rate'][i] = float('nan')  # Use NaN when there's no data
            else:
                storage['false neg rate'][i] = storage['false neg'][i] / storage['total positives'][i]
            
            # Handle division by zero for false positive rate
            if storage['total negatives'][i] == 0:
                storage['false pos rate'][i] = float('nan')  # Use NaN when there's no data
            else:
                storage['false pos rate'][i] = storage['false pos'][i] / storage['total negatives'][i]
            
        return pd.DataFrame(storage, index=self.labels)

    def process_reaction_times(self, data):
        """Process reaction time metrics."""
        rt_columns = [f'Letter{i}.RT' for i in range(1, 5)]
        rt_data = {label: [] for label in self.labels}
        
        # Collect non-zero, non-NaN reaction times
        for i, col in enumerate(rt_columns, 1):
            valid_times = data[col].dropna()[data[col] != 0]
            rt_data[self.labels[i]] = valid_times.tolist()
        
        # Combine all reaction times for 'entire' category
        rt_data['entire'] = [t for times in list(rt_data.values())[1:] for t in times]
        
        # Calculate statistics - handle empty series safely
        stats = {}
        for stat in self.metrics[7:]:
            stat_values = []
            for times in rt_data.values():
                if not times:  # If the list is empty
                    stat_values.append(float('nan'))
                else:
                    # Use get() with a default value to handle missing statistics
                    description = pd.Series(times).describe()
                    stat_values.append(description.get(stat, float('nan')))
            stats[stat] = stat_values
        
        return pd.DataFrame(stats, index=self.labels)

    def process_all(self):
        """Process all data files and save results."""
        # Keep track of valid data files and names
        valid_data_names = []
        
        for data, name in self.load_data():
            # Validate dataframe before processing
            if not self.validate_dataframe(data):
                print(f"Skipping file {name} due to missing required columns.")
                continue
                
            # Track valid data for indexing later
            valid_data_names.append(name)
                
            # Process metrics and merge results
            response_metrics = self.process_response_metrics(data)
            reaction_metrics = self.process_reaction_times(data)
            results = pd.merge(response_metrics, reaction_metrics, 
                             left_index=True, right_index=True)

            # Update results dictionary
            for label in self.labels:
                self.results_df_dict[label] = pd.concat(
                    [self.results_df_dict[label], results.loc[[label]]], 
                    ignore_index=True)

        # Save results
        for label in self.labels:
            df = self.results_df_dict[label]
            if not df.empty:  # Only save if we have results
                df.index = valid_data_names
                df.sort_index(inplace=True)
                # Save with utf-8-sig encoding for Excel compatibility
                df.to_csv(self.save_path / f'results_{label}.csv', encoding='utf-8-sig')

if __name__ == '__main__':
    import sys
    if len(sys.argv) > 2:
        LOAD_PATH = sys.argv[1]
        SAVE_PATH = sys.argv[2]
    else:
        LOAD_PATH = '/Users/medicabg/Documents/Projects/001_NPH/data/NIR/cog/ext'
        SAVE_PATH = '/Users/medicabg/Documents/Projects/001_NPH/data/NIR/cog/ext'
    
    processor = CognitiveDataProcessor(LOAD_PATH, SAVE_PATH)
    processor.process_all()