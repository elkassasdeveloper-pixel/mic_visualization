import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:mic_visualization/features/home/cubit/home_cubit.dart';
import 'package:mic_visualization/features/registered_mics/data/registered_mics_data_source.dart';

class RegisteredMicsScreen extends StatelessWidget {
  const RegisteredMicsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registered Mics')),
      body: BlocBuilder<HomeCubit, HomeState>(
        buildWhen: (prev, curr) => prev.registeredMics != curr.registeredMics,
        builder: (context, state) {
          if (state.registeredMics.isEmpty) {
            return const Center(child: Text('No mics registered yet'));
          }

          return SfDataGridTheme(
            data: const SfDataGridThemeData(headerColor: Colors.blue),
            child: SfDataGrid(
              source: RegisteredMicsDataSource(state.registeredMics, (
                copiedValue,
              ) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied: $copiedValue'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }),
              columnWidthMode: ColumnWidthMode.fill,
              gridLinesVisibility: GridLinesVisibility.both,
              headerGridLinesVisibility: GridLinesVisibility.both,
              columns: [
                GridColumn(
                  columnName: 'id',
                  label: const Center(
                    child: Text(
                      'ID',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                GridColumn(
                  columnName: 'name',
                  label: const Center(
                    child: Text(
                      'Name',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
