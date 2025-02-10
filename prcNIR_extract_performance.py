"""
Cognitive data output processor for the e-prime n-back paradigm v3.0
Ver. 2.2 (Optimized)
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
        """Load all CSV files from the specified directory."""
        file_list = list(self.load_path.glob('*.csv'))
        return [(pd.read_csv(f, encoding='utf-16'), f.stem[:9]) for f in file_list]

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

        # Calculate rates
        for i in range(5):
            storage['false neg rate'][i] = storage['false neg'][i] / storage['total positives'][i]
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
        
        # Calculate statistics
        stats = {stat: [pd.Series(times).describe()[stat] 
                       for times in rt_data.values()] 
                for stat in self.metrics[7:]}
        
        return pd.DataFrame(stats, index=self.labels)

    def process_all(self):
        """Process all data files and save results."""
        for data, name in self.load_data():
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
            df.index = [name for _, name in self.load_data()]
            df.sort_index(inplace=True)
            df.to_csv(self.save_path / f'results_{label}.csv')

if __name__ == '__main__':
    LOAD_PATH = '/Users/medicabg/Documents/Projects/001_NPH/data/NIR/cog/ext'
    SAVE_PATH = '/Users/medicabg/Documents/Projects/001_NPH/data/NIR/cog/ext'
    
    processor = CognitiveDataProcessor(LOAD_PATH, SAVE_PATH)
    processor.process_all()