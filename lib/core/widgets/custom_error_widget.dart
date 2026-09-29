import 'package:flutter/material.dart';

class CustomErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  final Function (BuildContext context) ?onclick;
  const CustomErrorWidget({super.key, required this.details,this.onclick  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body:
        SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [

              const Center(
                child: SizedBox(
                  width: 250,
                  height: 200,
                  child: Image(image: AssetImage('assets/images/error.gif')),
                ),
              ),

              Center(
                child: Container(
                  alignment: Alignment.center,
                  width: MediaQuery.of(context).size.width * .60,
                  height: MediaQuery.of(context).size.height * .40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.amber[300],
                    boxShadow: [
                      const BoxShadow(color: Colors.green, spreadRadius: 3),
                    ],
                  ),
                  child: Text(
                    ' Error!\n ${details.exception}',
                    style: const TextStyle(color: Colors.red, fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 15,),
              if(onclick !=null)
                GestureDetector(
                  onTap: (){
                    onclick!(context);
                  },
                  child: Container(
                    height: 40,
                    width: 220,
                    decoration: BoxDecoration(color: Colors.green,borderRadius: BorderRadius.circular(35)),
                    child: const Center(child: Text("StartAgain"),),
                  ),
                ),

            ],
          ),
        ),),
    );
  }
}
